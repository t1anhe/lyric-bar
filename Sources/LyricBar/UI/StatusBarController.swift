import AppKit
import SwiftUI

/// The menu bar icon and the popover it opens.
@MainActor
final class StatusBarController: NSObject {
    private let item: NSStatusItem
    private let popover = NSPopover()

    init(state: AppState, reloadLyrics: @escaping () -> Void) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "LyricBar")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(reloadLyrics: reloadLyrics).environmentObject(state)
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
