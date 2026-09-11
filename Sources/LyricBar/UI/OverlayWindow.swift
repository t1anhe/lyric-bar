import AppKit
import SwiftUI

/// Borderless, transparent, always-on-top panel that hosts the lyrics view.
final class OverlayPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayWindowController {
    private let panel: OverlayPanel
    private let state: AppState
    private var observers: [NSObjectProtocol] = []
    private static let frameKey = "overlayFrame"

    init(state: AppState) {
        self.state = state
        panel = OverlayPanel(frame: Self.initialFrame(fontSize: state.fontSize))
        panel.contentView = NSHostingView(rootView: OverlayView().environmentObject(state))
        setLocked(state.locked)

        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveFrame() }
            })
        }
    }

    func setLocked(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
        panel.isMovableByWindowBackground = !locked
    }

    /// The panel height follows the font size so the next line always fits.
    func setFontSize(_ fontSize: Double) {
        var frame = panel.frame
        let height = OverlayLayout.panelHeight(fontSize: fontSize)
        guard abs(frame.height - height) > 0.5 else { return }
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    func updateVisibility() {
        if state.shouldShowOverlay {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    private static func initialFrame(fontSize: Double) -> NSRect {
        let height = OverlayLayout.panelHeight(fontSize: fontSize)
        if let saved = UserDefaults.standard.string(forKey: frameKey) {
            var rect = NSRectFromString(saved)
            rect.size.height = height
            if rect.width > 100, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                return rect
            }
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(900, screen.width * 0.7)
        return NSRect(x: screen.midX - width / 2, y: screen.minY + 40, width: width, height: height)
    }
}
