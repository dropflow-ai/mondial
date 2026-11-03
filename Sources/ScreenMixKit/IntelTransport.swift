#if arch(x86_64)
import Foundation
import CoreGraphics
import IOKit
import IOKit.i2c

/// DDC/CI transport for Intel Macs, based on the classic `IOI2CInterface` API that is
/// exposed by the GPU framebuffer driver.
///
/// The logic follows the well known approach used by `ddcctl` and MonitorControl: find the
/// `IOFramebuffer` that belongs to a `CGDirectDisplayID`, open its I2C bus and send raw
/// DDC/CI packets.
final class IntelTransport: DDCTransport {
    private let framebuffer: io_service_t
    private let replyTransactionType: IOOptionBits

    var debugDescription: String {
        "IOI2CInterface (Intel), framebuffer=\(framebuffer), replyType=\(replyTransactionType)"
    }

    init?(displayID: CGDirectDisplayID) {
        guard CGDisplayIsBuiltin(displayID) == 0 else { return nil }
        guard let framebuffer = Self.framebufferPort(for: displayID) else { return nil }
        guard let replyType = Self.supportedReplyTransactionType() else {
            IOObjectRelease(framebuffer)
            return nil
        }
        self.framebuffer = framebuffer
        self.replyTransactionType = replyType
    }

    deinit {
        IOObjectRelease(framebuffer)
    }

    // MARK: - DDC

    func readVCP(_ code: UInt8) -> (current: UInt16, max: UInt16)? {
        var packet: [UInt8] = [0x51, 0x82, 0x01, code, 0x00]
        packet[4] = 0x6E ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3]

        var reply = [UInt8](repeating: 0, count: 11)
        for _ in 0 ..< 3 {
            usleep(10_000)
            var request = IOI2CRequest()
            request.commFlags = 0
            request.sendAddress = 0x6E
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.sendBytes = UInt32(packet.count)
            request.minReplyDelay = 10
            request.replyAddress = 0x6F
            request.replySubAddress = 0x51
            request.replyTransactionType = replyTransactionType
            request.replyBytes = UInt32(reply.count)

            let sent: Bool = packet.withUnsafeMutableBufferPointer { sendBuffer in
                reply.withUnsafeMutableBufferPointer { replyBuffer in
                    request.sendBuffer = vm_address_t(bitPattern: sendBuffer.baseAddress)
                    request.replyBuffer = vm_address_t(bitPattern: replyBuffer.baseAddress)
                    return Self.send(request: &request, to: framebuffer)
                }
            }
            guard sent else { continue }
            if let value = Self.parseReply(reply, code: code) { return value }
        }
        return nil
    }

    @discardableResult
    func writeVCP(_ code: UInt8, value: UInt16) -> Bool {
        var packet: [UInt8] = [0x51, 0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF), 0x00]
        packet[6] = 0x6E ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4] ^ packet[5]

        var acknowledged = false
        for _ in 0 ..< 2 {
            usleep(12_000)
            var request = IOI2CRequest()
            request.commFlags = 0
            request.sendAddress = 0x6E
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.sendBytes = UInt32(packet.count)
            request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
            request.replyBytes = 0

            let sent: Bool = packet.withUnsafeMutableBufferPointer { sendBuffer in
                request.sendBuffer = vm_address_t(bitPattern: sendBuffer.baseAddress)
                return Self.send(request: &request, to: framebuffer)
            }
            if sent { acknowledged = true }
        }
        return acknowledged
    }

    /// Identical reply layout as on Apple Silicon - checksum is validated when present.
    static func parseReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= 10 else { return nil }
        guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == code else { return nil }
        let maxValue = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let currentValue = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maxValue > 0 else { return nil }
        return (min(currentValue, maxValue), maxValue)
    }

    // MARK: - IOKit plumbing

    private static func send(request: inout IOI2CRequest, to framebuffer: io_service_t) -> Bool {
        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS, busCount > 0 else {
            return false
        }
        for bus in 0 ..< busCount {
            var interface: io_service_t = 0
            guard IOFBCopyI2CInterfaceForBus(framebuffer, IOOptionBits(bus), &interface) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(interface) }

            var connect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, 0, &connect) == KERN_SUCCESS, let connect else {
                continue
            }
            defer { IOI2CInterfaceClose(connect, 0) }

            guard IOI2CSendRequest(connect, 0, &request) == KERN_SUCCESS else { continue }
            guard request.result == KERN_SUCCESS else { continue }
            return true
        }
        return false
    }

    private static func supportedReplyTransactionType() -> IOOptionBits? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceNameMatching("IOFramebufferI2CInterface"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties else { continue }
            guard let dictionary = properties.takeRetainedValue() as? [String: Any],
                  let types = dictionary["IOI2CTransactionTypes"] as? UInt64 else { continue }

            if (1 << UInt64(kIOI2CDDCciReplyTransactionType)) & types != 0 {
                return IOOptionBits(kIOI2CDDCciReplyTransactionType)
            }
            if (1 << UInt64(kIOI2CSimpleTransactionType)) & types != 0 {
                return IOOptionBits(kIOI2CSimpleTransactionType)
            }
        }
        return nil
    }

    /// Finds the `IOFramebuffer` service that belongs to a display by matching
    /// vendor / product / serial number from the display's information dictionary.
    private static func framebufferPort(for displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOFramebuffer"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)

        while true {
            let port = IOIteratorNext(iterator)
            if port == 0 { break }
            guard let info = IODisplayCreateInfoDictionary(port, 0)?.takeRetainedValue() as? [String: Any] else {
                IOObjectRelease(port)
                continue
            }
            let portVendor = (info["DisplayVendorID"] as? NSNumber)?.uint32Value ?? 0
            let portModel = (info["DisplayProductID"] as? NSNumber)?.uint32Value ?? 0
            let portSerial = (info["DisplaySerialNumber"] as? NSNumber)?.uint32Value ?? 0
            let matches = portVendor == vendor && portModel == model && portSerial == serial

            var busCount: IOItemCount = 0
            let hasBus = IOFBGetI2CInterfaceCount(port, &busCount) == KERN_SUCCESS && busCount > 0

            if matches && hasBus { return port }
            IOObjectRelease(port)
        }
        return nil
    }
}
#endif
