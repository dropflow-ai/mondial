import Foundation
import CoreGraphics

/// VCP (Virtual Control Panel) codes from the MCCS specification.
public enum VCP: UInt8 {
    case brightness = 0x10
    case contrast = 0x12
    case volume = 0x62
    case mute = 0x8D
    case inputSource = 0x60
    case powerMode = 0xD6

    public var localizedName: String {
        switch self {
        case .brightness: return L("Helligkeit", "Brightness")
        case .contrast: return L("Kontrast", "Contrast")
        case .volume: return L("Lautstärke", "Volume")
        case .mute: return L("Stumm", "Mute")
        case .inputSource: return L("Eingang", "Input")
        case .powerMode: return L("Energie sparen", "Power mode")
        }
    }
}

/// A single DDC/CI capable display connection.
public protocol DDCTransport: AnyObject {
    /// Human readable description of the transport, used by `mondialctl doctor`.
    var debugDescription: String { get }
    /// Reads a VCP value. Returns `nil` when the display does not answer or does not support
    /// the given code.
    func readVCP(_ code: UInt8) -> (current: UInt16, max: UInt16)?
    /// Writes a VCP value. Returns `false` when the display did not acknowledge the packet.
    func writeVCP(_ code: UInt8, value: UInt16) -> Bool
}

/// A physical display as seen by macOS, optionally with a DDC transport attached.
public struct PhysicalDisplay: Identifiable {
    public let id: String
    public let displayID: CGDirectDisplayID
    public let name: String
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32
    public let isBuiltin: Bool
    public let transport: DDCTransport?

    public var hasDDC: Bool { transport != nil }
    public var debugDescription: String {
        transport?.debugDescription ?? "kein DDC-Transport"
    }

    public func read(_ vcp: VCP) -> (current: UInt16, max: UInt16)? {
        transport?.readVCP(vcp.rawValue)
    }

    @discardableResult
    public func write(_ vcp: VCP, value: UInt16) -> Bool {
        transport?.writeVCP(vcp.rawValue, value: value) ?? false
    }
}

enum DDCConstants {
    /// 7 bit I2C address of the DDC/CI host (monitor side: 0x37 << 1 = 0x6E).
    static let chipAddress: UInt32 = 0x37
    /// Chip address used by the MCDP29xx HDMI controller on Apple Silicon Macs.
    static let mcdpChipAddress: UInt32 = 0xB7
    /// DDC/CI data address (offset in the I2C transaction).
    static let dataAddress: UInt32 = 0x51
}
