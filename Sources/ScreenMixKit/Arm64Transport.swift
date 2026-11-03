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
/// Two different read conventions exist in the wild (they differ in the checksum seed and in
/// the I2C offset that is used for the reply), so both are tried and the working one is
/// remembered for the lifetime of the object.
final class Arm64Transport: DDCTransport {
    private let api = PrivateAPI.shared
    private let service: UnsafeMutableRawPointer
    private let chipAddress: UInt32

    private enum ReadStrategy {
        case dataAddress   // checksum includes 0x51, reply read at offset 0x51, 12 bytes
        case zeroOffset    // checksum without 0x51, reply read at offset 0x00, 11 bytes
    }

    private var strategy: ReadStrategy?

    var debugDescription: String {
        let strategyName: String
        switch strategy {
        case .dataAddress: strategyName = "data-address"
        case .zeroOffset: strategyName = "zero-offset"
        case nil: strategyName = "auto"
        }
        return "IOAVService (Apple Silicon), chip=0x\(String(chipAddress, radix: 16)), read=\(strategyName)"
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
        let candidates: [ReadStrategy] = strategy.map { [$0] } ?? [.dataAddress, .zeroOffset]
        // Some panels (Samsung ViewFinity among them) answer slowly or drop the first
        // request after the monitor woke up, so retry with a growing pause before giving up.
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
        return acknowledged
    }
}
#endif
