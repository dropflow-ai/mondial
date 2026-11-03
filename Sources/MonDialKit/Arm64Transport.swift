#if arch(arm64)
import Foundation
import CoreGraphics
import IOKit

/// DDC/CI transport for Apple Silicon Macs.
///
/// Apple Silicon does not expose the classic `IOI2CInterface` API anymore. Instead DDC
/// packets are pushed through the display coprocessor (`DCPAVServiceProxy`) using the private
/// `IOAVServiceReadI2C` / `IOAVServiceWriteI2C` functions.
///
/// Two things differ between monitors and Macs:
///   * the I²C chip address: `0x37` for DisplayPort/USB-C, `0xB7` when the display hangs on
///     an HDMI port driven by the MCDP29xx controller
///   * the read convention: checksum with or without the `0x51` data address, reply at
///     offset `0x51` (12 bytes) or offset `0` (11 bytes)
///
/// Both are detected at runtime: the first read that fails triggers a switch to the other
/// chip address, and a failed read also tries the other reply convention.
final class Arm64Transport: DDCTransport {
    private let api = PrivateAPI.shared
    private let service: UnsafeMutableRawPointer
    private var chipAddress: UInt32

    private enum ReadStrategy {
        case dataAddress   // checksum includes 0x51, reply read at offset 0x51, 12 bytes
        case zeroOffset    // checksum without 0x51, reply read at offset 0x00, 11 bytes
    }

    private var strategy: ReadStrategy?
    private var chipCalibrated = false
    private var didSwitchChip = false
    private var writeVerified = false

    var debugDescription: String {
        let strategyName: String
        switch strategy {
        case .dataAddress: strategyName = "data-address"
        case .zeroOffset: strategyName = "zero-offset"
        case nil: strategyName = "auto"
        }
        let switched = didSwitchChip ? " (automatisch korrigiert)" : ""
        let pointer = String(UInt(bitPattern: service), radix: 16)
        return "IOAVService, chip=0x\(String(chipAddress, radix: 16))\(switched), read=\(strategyName), svc=0x\(pointer)"
    }

    init(service: UnsafeMutableRawPointer, chipAddress: UInt32) {
        self.service = service
        self.chipAddress = chipAddress
    }

    // MARK: - Low level I2C

    private func write(_ bytes: inout [UInt8], offset: UInt32) -> kern_return_t {
        guard let writeI2C = api.writeI2C else { return kern_return_t(KERN_FAILURE) }
        let length = UInt32(bytes.count)
        return bytes.withUnsafeMutableBytes { buffer in
            writeI2C(service, chipAddress, offset, buffer.baseAddress, length)
        }
    }

    private func read(offset: UInt32, into buffer: inout [UInt8], length: UInt32) -> kern_return_t {
        guard let readI2C = api.readI2C else { return kern_return_t(KERN_FAILURE) }
        return buffer.withUnsafeMutableBytes { raw in
            readI2C(service, chipAddress, offset, raw.baseAddress, length)
        }
    }

    // MARK: - VCP access

    func readVCP(_ code: UInt8) -> (current: UInt16, max: UInt16)? {
        if let value = readOnce(code) {
            chipCalibrated = true
            return value
        }

        // Nothing came back. Either the display is asleep, DDC/CI is off, or we are talking
        // to the wrong chip address. Try the other one once before reporting a failure.
        guard !chipCalibrated else { return nil }
        chipCalibrated = true

        let original = chipAddress
        chipAddress = Self.alternateChip(for: original)
        if let value = readOnce(code) {
            didSwitchChip = true
            return value
        }
        chipAddress = original
        return nil
    }

    /// Single-shot probe used while matching displays to DCP proxies: no retry loop and no
    /// chip switching, just the question "is anybody on the other end of this proxy?".
    func probe(_ code: UInt8) -> Bool {
        for candidate in [ReadStrategy.dataAddress, .zeroOffset] {
            if attemptRead(code, strategy: candidate) != nil {
                strategy = candidate
                return true
            }
        }
        return false
    }

    private static func alternateChip(for address: UInt32) -> UInt32 {
        address == DDCConstants.chipAddress ? DDCConstants.mcdpChipAddress : DDCConstants.chipAddress
    }

    /// Three attempts with both reply conventions - slow panels (Samsung among them) drop the
    /// first request after waking up.
    private func readOnce(_ code: UInt8) -> (current: UInt16, max: UInt16)? {
        let candidates: [ReadStrategy] = strategy.map { [$0] } ?? [.dataAddress, .zeroOffset]
        for attempt in 0 ..< 3 {
            for candidate in candidates {
                if let value = attemptRead(code, strategy: candidate) {
                    strategy = candidate
                    return value
                }
            }
            if attempt < 2 { usleep(60_000) }
        }
        return nil
    }

    private func attemptRead(_ code: UInt8, strategy: ReadStrategy) -> (current: UInt16, max: UInt16)? {
        var request: [UInt8] = [0x82, 0x01, code, 0x00]
        request[3] = strategy == .dataAddress
            ? 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ code
            : 0x6E ^ 0x82 ^ 0x01 ^ code

        for _ in 0 ..< 2 {
            usleep(10_000)
            _ = write(&request, offset: DDCConstants.dataAddress)
        }

        usleep(strategy == .dataAddress ? 50_000 : 40_000)

        let usesDataAddress = (strategy == .dataAddress)
        var reply = [UInt8](repeating: 0, count: 12)
        let status = read(offset: usesDataAddress ? DDCConstants.dataAddress : 0,
                          into: &reply,
                          length: usesDataAddress ? 12 : 11)
        guard status == KERN_SUCCESS else { return nil }
        return Self.parseReply(reply, code: code)
    }

    /// Validates a "Get VCP Feature Reply" packet and extracts current/maximum value.
    /// Layout: [0x6E, 0x88, 0x02, result, vcp, type, maxHi, maxLo, curHi, curLo, checksum]
    static func parseReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= 10 else { return nil }
        guard reply[2] == 0x02 else { return nil }
        guard reply[3] == 0x00 else { return nil }
        guard reply[4] == code else { return nil }

        let maxValue = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let currentValue = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maxValue > 0 else { return nil }
        return (min(currentValue, maxValue), maxValue)
    }

    @discardableResult
    func writeVCP(_ code: UInt8, value: UInt16) -> Bool {
        var packet: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF), 0x00]
        packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]

        var acknowledged = false
        for _ in 0 ..< 3 {
            usleep(12_000)
            if write(&packet, offset: DDCConstants.dataAddress) == KERN_SUCCESS {
                acknowledged = true
            }
        }
        usleep(8_000)

        // A write that the I²C layer accepts is not proof that the monitor understood it.
        // If the panel is readable and the value did not change, the chip address is wrong.
        // Only check this once: doing it on every slider step would double the latency.
        if acknowledged, !writeVerified {
            writeVerified = true
            guard let reply = readOnce(code) else { return acknowledged }
            if reply.current != value {
                let original = chipAddress
                chipAddress = Self.alternateChip(for: original)
                if write(&packet, offset: DDCConstants.dataAddress) == KERN_SUCCESS,
                   let check = readOnce(code), check.current == value {
                    didSwitchChip = true
                    return true
                }
                chipAddress = original
            }
        }
        return acknowledged
    }
}
#endif
