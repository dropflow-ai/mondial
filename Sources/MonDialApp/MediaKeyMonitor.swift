import Cocoa
import ApplicationServices

/// Intercepts the hardware media keys (brightness and volume) so they control the external
/// display instead of doing nothing at all.
///
/// Without an internal display a Mac mini has nothing to apply the brightness keys to, which
/// is why they appear to be dead. A `CGEventTap` on `NX_SYSDEFINED` lets us catch them first
/// and swallow the event. This requires the "Bedienungshilfen" (Accessibility) permission.
final class MediaKeyMonitor {
    static let shared = MediaKeyMonitor()

    enum MediaKey: Int32 {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    var onKey: ((MediaKey) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastHandled = Date.distantPast

    var isRunning: Bool { eventTap != nil }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: mediaKeyTapCallback,
                                          userInfo: nil) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// macOS disables slow event taps; this switches the tap back on.
    func reEnable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    fileprivate func shouldHandle(_ key: MediaKey) -> Bool {
        // Rate limit key repeats: the media keys fire very quickly when held down.
        let now = Date()
        guard now.timeIntervalSince(lastHandled) > 0.03 else { return false }
        lastHandled = now
        onKey?(key)
        return true
    }
}

private let mediaKeyTapCallback: CGEventTapCallBack = { proxy, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MediaKeyMonitor.shared.reEnable()
        return Unmanaged.passUnretained(event)
    }

    guard let nsEvent = NSEvent(cgEvent: event),
          nsEvent.type == .systemDefined,
          nsEvent.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }

    let data1 = nsEvent.data1
    let keyCode = Int32((data1 & 0xFFFF_0000) >> 16)
    let keyFlags = data1 & 0x0000_FFFF
    let keyState = (keyFlags & 0xFF00) >> 8

    // 0x0A = key down
    guard keyState == 0x0A else { return Unmanaged.passUnretained(event) }
    guard let mediaKey = MediaKeyMonitor.MediaKey(rawValue: keyCode) else {
        return Unmanaged.passUnretained(event)
    }

    if MediaKeyMonitor.shared.shouldHandle(mediaKey) {
        return nil // swallow the event so macOS does not beep or act on it
    }
    return Unmanaged.passUnretained(event)
}
