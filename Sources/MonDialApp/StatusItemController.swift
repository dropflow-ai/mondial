import AppKit
import SwiftUI
import MonDialKit

/// Owns the menu bar item and the popover behind it.
///
/// `MenuBarExtra` was the obvious choice, but its window keeps the height it had when it was
/// first shown: opening the settings section pushed the header (and with it the gear that
/// closes it again) out of sight. An `NSPopover` lets us set `contentSize` whenever the
/// content changes, so the panel grows and shrinks with what is in it.
final class StatusItemController: NSObject, NSPopoverDelegate {
    static let shared = StatusItemController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var hosting: NSHostingController<AnyView>?
    private let width: CGFloat = 340

    private override init() { super.init() }

    func install() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "MonDial")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let root = PopoverView(store: DisplayStore.shared) { [weak self] in
            self?.resize()
        }
        let controller = NSHostingController(rootView: AnyView(root))
        controller.sizingOptions = [.preferredContentSize]
        hosting = controller
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            show()
        }
    }

    private func show() {
        guard let button = statusItem.button else { return }
        DisplayStore.shared.refresh()
        resize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Fits the popover to the height the SwiftUI content actually needs.
    func resize() {
        guard let controller = hosting else { return }
        controller.view.layoutSubtreeIfNeeded()

        // `preferredContentSize` is maintained by the hosting controller itself; `fittingSize`
        // is the fallback for the moment before the first layout pass has happened.
        var height = controller.preferredContentSize.height
        if height < 100 { height = controller.view.fittingSize.height }
        if height < 100 { height = 360 }

        let screenLimit = (NSScreen.main?.visibleFrame.height ?? 900) - 40
        let target = NSSize(width: width, height: min(max(ceil(height), 120), screenLimit))
        guard popover.contentSize != target else { return }
        popover.contentSize = target
    }

    func popoverDidClose(_ notification: Notification) {
        // A closed popover must not keep the last expanded size.
        resize()
    }
}
