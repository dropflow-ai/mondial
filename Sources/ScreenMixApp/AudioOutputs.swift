import Foundation
import CoreAudio
import SwiftUI

/// One selectable audio output of the Mac (internal speakers, the monitor's speakers,
/// headphones, AirPods …).
struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let symbol: String
    let detail: String
}

/// Thin wrapper around the CoreAudio HAL: enumerate outputs, read and switch the default.
enum AudioOutputs {
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func all() -> [AudioOutputDevice] {
        var property = address(kAudioHardwarePropertyDevices)
        var dataSize: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &dataSize) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &property, 0, nil, &dataSize, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard outputChannels(id) > 0, let name = name(id), !name.isEmpty else { return nil }
            let transport = transportType(id)
            return AudioOutputDevice(id: id,
                                     name: name,
                                     symbol: symbol(for: transport),
                                     detail: label(for: transport))
        }
    }

    static func current() -> AudioDeviceID? {
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &property, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    @discardableResult
    static func setDefault(_ deviceID: AudioDeviceID) -> Bool {
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &property, 0, nil, size, &value)

        var systemProperty = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        _ = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                       &systemProperty, 0, nil, size, &value)
        return status == noErr
    }

    // MARK: - Device details

    private static func outputChannels(_ id: AudioDeviceID) -> Int {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr, size > 0 else { return 0 }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, raw) == noErr else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(_ id: AudioDeviceID) -> String? {
        var property = address(kAudioObjectPropertyName)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr else { return nil }
        let text = value as String
        return text.isEmpty ? nil : text
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var property = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func symbol(for transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "hifispeaker.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort: return "display"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual: return "waveform"
        default: return "speaker.wave.2.fill"
        }
    }

    private static func label(for transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "intern"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeVirtual: return "virtuell"
        default: return "Gerät"
        }
    }
}

/// Observable wrapper the popover binds to.
final class AudioOutputStore: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var currentID: AudioDeviceID?

    var currentName: String {
        devices.first { $0.id == currentID }?.name ?? "Keine Ausgabe"
    }

    func refresh() {
        devices = AudioOutputs.all()
        currentID = AudioOutputs.current()
    }

    func select(_ device: AudioOutputDevice) {
        AudioOutputs.setDefault(device.id)
        // Give the HAL a moment before reading the new default back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refresh()
        }
    }
}
