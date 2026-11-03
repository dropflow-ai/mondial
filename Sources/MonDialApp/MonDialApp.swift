import SwiftUI
import AppKit
import MonDialKit

@main
struct MonDialApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The menu bar item and its popover are owned by StatusItemController, because
        // MenuBarExtra cannot change its window height once it is on screen.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        terminateIfAlreadyRunning()

        DisplayStore.shared.refresh(force: true)
        StatusItemController.shared.install()

        HotKeyManager.shared.onAction = { action in
            DisplayStore.shared.handle(action)
        }
        if Preferences.hotKeysEnabled {
            HotKeyManager.shared.start()
        }

        MediaKeyMonitor.shared.onKey = { key in
            DisplayStore.shared.handle(mediaKey: key)
        }
        if Preferences.mediaKeysEnabled {
            let started = MediaKeyMonitor.shared.start()
            if !started {
                Preferences.mediaKeysEnabled = false
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            DisplayStore.shared.refresh(force: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.stop()
        MediaKeyMonitor.shared.stop()
        SoftwareBrightness.resetAll()
    }

    private func terminateIfAlreadyRunning() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        if instances.count > 1 {
            NSApplication.shared.terminate(nil)
        }
    }
}
