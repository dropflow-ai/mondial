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
        guard let view = hosting?.view else { return }
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        let height = min(max(ceil(fitting.height), 120), 900)
        let target = NSSize(width: width, height: height)
        guard popover.contentSize != target else { return }
        popover.contentSize = target
    }

    func popoverDidClose(_ notification: Notification) {
        // A closed popover must not keep the last expanded size.
        resize()
    }
}
