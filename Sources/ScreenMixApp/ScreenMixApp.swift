import SwiftUI
import AppKit
import ScreenMixKit

@main
struct ScreenMixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = DisplayStore.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Image(systemName: "sun.max.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        terminateIfAlreadyRunning()

        DisplayStore.shared.refresh(force: true)

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
