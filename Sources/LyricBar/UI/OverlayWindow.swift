import AppKit
import ApplicationServices
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

/// Session-wide event tap that turns a right-button drag over the overlay into
/// a window move and swallows those events, so the app underneath never sees
/// them. The overlay itself ignores mouse events (it is click-through), which
/// is why a tap is needed. Requires the Accessibility permission; without it
/// `install()` returns false.
@MainActor
final class RightDragTap {
    weak var panel: NSPanel?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var tap: CFMachPort?
    private var dragOffset: NSPoint?

    var isInstalled: Bool { tap != nil }
    var isDragging: Bool { dragOffset != nil }

    func install() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<RightDragTap>.fromOpaque(refcon).takeUnretainedValue()
                return MainActor.assumeIsolated { controller.handle(type: type, event: event) }
            },
            userInfo: refcon
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }
        guard let panel, panel.isVisible else { return passThrough }
        let mouse = NSEvent.mouseLocation
        switch type {
        case .rightMouseDown:
            guard panel.frame.contains(mouse) else { return passThrough }
            dragOffset = NSPoint(x: mouse.x - panel.frame.origin.x, y: mouse.y - panel.frame.origin.y)
            onDragBegan?()
            return nil
        case .rightMouseDragged:
            guard let offset = dragOffset else { return passThrough }
            panel.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
            return nil
        case .rightMouseUp:
            guard dragOffset != nil else { return passThrough }
            dragOffset = nil
            onDragEnded?()
            return nil
        default:
            return passThrough
        }
    }
}

@MainActor
final class OverlayWindowController {
    private let panel: OverlayPanel
    private let state: AppState
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var accessibilityTimer: Timer?
    private let rightDrag = RightDragTap()

    private var faded = false
    private var suppressFadeUntil = Date.distantPast
    /// The window is catching the mouse because ⌥ is held over it.
    private var optionDragArmed = false
    private var leftButtonWasDown = false
    private var frameAtLeftButtonDown: NSRect?

    private static let frameKey = "overlayFrame"
    private static let accessibilityPromptedKey = "accessibilityPrompted"
    private static let fadedAlpha: CGFloat = 0.15
    private static let snapDistance: CGFloat = 24
    private static let centerSnapDistance: CGFloat = 32

    init(state: AppState) {
        self.state = state
        panel = OverlayPanel(frame: Self.initialFrame(fontSize: state.fontSize))
        panel.contentView = NSHostingView(rootView: OverlayView().environmentObject(state))
        panel.ignoresMouseEvents = true

        rightDrag.panel = panel
        rightDrag.onDragBegan = { [weak self] in self?.dragBegan() }
        rightDrag.onDragEnded = { [weak self] in self?.dragEnded() }

        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveFrame() }
            })
        }

        // Poll the mouse: the panel ignores mouse events while click-through, so
        // it gets no hover or modifier events of its own. 20 Hz costs nothing.
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollMouse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: Right-drag (Accessibility)

    /// Ask for the Accessibility permission once, and install the right-drag tap
    /// as soon as it is granted (the user may grant it later in System Settings).
    func setUpRightDrag() {
        let defaults = UserDefaults.standard
        if !AXIsProcessTrusted(), !defaults.bool(forKey: Self.accessibilityPromptedKey) {
            defaults.set(true, forKey: Self.accessibilityPromptedKey)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        tryInstallRightDrag()
        if !rightDrag.isInstalled {
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tryInstallRightDrag() }
            }
            RunLoop.main.add(timer, forMode: .common)
            accessibilityTimer = timer
        }
    }

    private func tryInstallRightDrag() {
        let trusted = AXIsProcessTrusted()
        state.accessibilityTrusted = trusted
        guard trusted, !rightDrag.isInstalled else { return }
        if rightDrag.install() {
            Log.info("Right-drag enabled (Accessibility granted)")
            accessibilityTimer?.invalidate()
            accessibilityTimer = nil
        } else {
            // Happens when the grant is stale (e.g. the app was rebuilt with a new
            // ad-hoc signature): remove and re-add LyricBar in System Settings.
            state.accessibilityTrusted = false
            Log.warn("Accessibility looks granted but the event tap could not be created")
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Mouse polling: hover fade, ⌥-drag, snap after a drag

    private func pollMouse() {
        guard panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let inside = panel.frame.insetBy(dx: -4, dy: -4).contains(mouse)
        let leftDown = NSEvent.pressedMouseButtons & 1 != 0
        let optionHeld = NSEvent.modifierFlags.contains(.option)

        // ⌥-drag: while Option is held over the overlay the window catches the
        // mouse, so an ordinary drag moves it. Back to click-through once both
        // the key and the button are released.
        if optionHeld, inside, !optionDragArmed {
            optionDragArmed = true
            panel.ignoresMouseEvents = false
        } else if optionDragArmed, !leftDown, !(optionHeld && inside) {
            optionDragArmed = false
            panel.ignoresMouseEvents = true
        }

        // End of an ⌥-drag: the button came up after the window moved.
        if leftDown, !leftButtonWasDown {
            frameAtLeftButtonDown = optionDragArmed ? panel.frame : nil
        } else if !leftDown, leftButtonWasDown {
            if let before = frameAtLeftButtonDown, before.origin != panel.frame.origin {
                dragEnded()
            }
            frameAtLeftButtonDown = nil
        }
        leftButtonWasDown = leftDown

        let dragging = rightDrag.isDragging || optionDragArmed
        if state.dragging != dragging { state.dragging = dragging }
        setFaded(inside && !dragging && Date() >= suppressFadeUntil)
    }

    private func dragBegan() {
        state.dragging = true
        setFaded(false)
    }

    private func dragEnded() {
        snapToEdges()
        state.dragging = rightDrag.isDragging || optionDragArmed
        suppressFadeUntil = Date().addingTimeInterval(1.0)
        saveFrame()
    }

    /// Snap to the screen the overlay is on: horizontally only to the centre (the
    /// window frame is invisible and the text is centred in it, so snapping the
    /// frame to the left or right edge just leaves the text floating mid-half),
    /// vertically to the top of the Dock, the bottom of the menu bar and the
    /// middle. Always keeps the window on screen.
    func snapToEdges() {
        var frame = panel.frame
        let screen = NSScreen.screens.max { a, b in
            Self.area(a.frame.intersection(frame)) < Self.area(b.frame.intersection(frame))
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        func snap(_ value: CGFloat, to candidates: [CGFloat], within distance: CGFloat) -> CGFloat {
            guard let nearest = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
                  abs(nearest - value) <= distance else { return value }
            return nearest
        }
        frame.origin.x = snap(frame.origin.x, to: [visible.midX - frame.width / 2], within: Self.centerSnapDistance)
        frame.origin.y = snap(frame.origin.y, to: [visible.minY, visible.maxY - frame.height], within: Self.snapDistance)
        frame.origin.y = snap(frame.origin.y, to: [visible.midY - frame.height / 2], within: Self.centerSnapDistance)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)

        if frame.origin != panel.frame.origin {
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    private static func area(_ rect: NSRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private func setFaded(_ fade: Bool) {
        guard fade != faded else { return }
        faded = fade
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = fade ? Self.fadedAlpha : 1
        }
    }

    // MARK: Geometry

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

    /// Debug helper: move the panel and run the snap logic.
    func debugMove(to origin: NSPoint) {
        panel.setFrameOrigin(origin)
        dragEnded()
        Log.info("debug move -> \(NSStringFromRect(panel.frame))")
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
