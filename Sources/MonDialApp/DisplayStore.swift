import Foundation
import Combine
import MonDialKit

/// Holds the list of displays shown in the menu bar popover and dispatches key commands to
/// the "primary" display (the first external one, which is what people usually want to dim).
final class DisplayStore: ObservableObject {
    static let shared = DisplayStore()

    @Published private(set) var displays: [DisplayController] = []
    @Published private(set) var isRefreshing = false
    @Published var message: String?

    private var controllers: [String: DisplayController] = [:]
    private let scanQueue = DispatchQueue(label: "ch.dropflow.mondial.scan")

    private init() {}

    var primaryDisplay: DisplayController? {
        displays.first(where: { !$0.isBuiltin && $0.supportsBrightness })
            ?? displays.first(where: { !$0.isBuiltin })
            ?? displays.first
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        scanQueue.async {
            if force { DisplayManager.invalidateCache() }
            let physicalDisplays = DisplayManager.refresh()
            DispatchQueue.main.async {
                var updated: [DisplayController] = []
                for physical in physicalDisplays {
                    if let existing = self.controllers[physical.id] {
                        updated.append(existing)
                    } else {
                        let controller = DisplayController(display: physical)
                        self.controllers[physical.id] = controller
                        controller.refresh()
                        updated.append(controller)
                    }
                }
                let alive = Set(updated.map(\.id))
                self.controllers = self.controllers.filter { alive.contains($0.key) }
                self.displays = updated
                self.isRefreshing = false
            }
        }
    }

    // MARK: - Keyboard / media key actions

    func handle(_ action: HotKeyAction) {
        guard let display = primaryDisplay else { return }
        let step = Preferences.stepSize
        switch action {
        case .brightnessUp: display.stepBrightness(by: step)
        case .brightnessDown: display.stepBrightness(by: -step)
        case .volumeUp: display.stepVolume(by: step)
        case .volumeDown: display.stepVolume(by: -step)
        case .mute: display.toggleMute()
        }
    }

    func handle(mediaKey: MediaKeyMonitor.MediaKey) {
        guard let display = primaryDisplay else { return }
        let step = Preferences.stepSize
        switch mediaKey {
        case .brightnessUp: display.stepBrightness(by: step)
        case .brightnessDown: display.stepBrightness(by: -step)
        case .soundUp: display.stepVolume(by: step)
        case .soundDown: display.stepVolume(by: -step)
        case .mute: display.toggleMute()
        }
    }
}
