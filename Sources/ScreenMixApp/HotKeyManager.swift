import Foundation
import Carbon.HIToolbox

enum HotKeyAction: UInt32 {
    case brightnessUp = 1
    case brightnessDown = 2
    case volumeUp = 3
    case volumeDown = 4
    case mute = 5
}

/// Global hotkeys via the Carbon event manager.
///
/// Carbon is deprecated but remains the only way to register system-wide shortcuts that do
/// not require the Accessibility permission - which is exactly what we want as a default.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onAction: ((HotKeyAction) -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var isRunning = false

    private let signature: OSType = 0x534D4958 // 'SMIX'

    func start() {
        guard !isRunning else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         hotKeyCallback,
                                         1,
                                         &eventType,
                                         Unmanaged.passUnretained(self).toOpaque(),
                                         &handlerRef)
        guard status == noErr else { return }

        register(.brightnessUp, keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey | optionKey))
        register(.brightnessDown, keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey | optionKey))
        register(.volumeUp, keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey | optionKey | shiftKey))
        register(.volumeDown, keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey | optionKey | shiftKey))
        register(.mute, keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))

        isRunning = true
    }

    func stop() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        isRunning = false
    }

    private func register(_ action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: action.rawValue)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        }
    }

    fileprivate func handle(id: UInt32) {
        guard let action = HotKeyAction(rawValue: id) else { return }
        onAction?(action)
    }
}

private let hotKeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return OSStatus(eventNotHandledErr) }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handle(id: hotKeyID.id)
    return noErr
}
