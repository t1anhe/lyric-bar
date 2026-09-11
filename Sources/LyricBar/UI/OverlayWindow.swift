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
    private var hoverTimer: Timer?
    private var movable = false
    private var faded = false
    private static let frameKey = "overlayFrame"
    private static let fadedAlpha: CGFloat = 0.15

    init(state: AppState) {
        self.state = state
        panel = OverlayPanel(frame: Self.initialFrame(fontSize: state.fontSize))
        panel.contentView = NSHostingView(rootView: OverlayView().environmentObject(state))
        setMovable(state.movable)

        // Poll the mouse: the panel ignores mouse events while click-through, so
        // it gets no hover events of its own. 10 Hz is plenty and costs nothing.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer

        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveFrame() }
            })
        }
    }

    func setMovable(_ movable: Bool) {
        self.movable = movable
        panel.ignoresMouseEvents = !movable
        panel.isMovableByWindowBackground = movable
        if movable { setFaded(false) }
    }

    /// Fade the lyrics while the mouse is over them so whatever is underneath
    /// stays readable and clickable (clicks already pass through).
    private func checkHover() {
        guard panel.isVisible, !movable else { return }
        let inside = panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        setFaded(inside)
    }

    private func setFaded(_ fade: Bool) {
        guard fade != faded else { return }
        faded = fade
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = fade ? Self.fadedAlpha : 1
        }
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
