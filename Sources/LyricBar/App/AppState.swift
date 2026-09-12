import Combine
import Foundation

/// Shared observable state for the UI. Main-actor only.
@MainActor
final class AppState: ObservableObject {
    @Published var snapshot: PlayerSnapshot?
    @Published var track: TrackInfo?
    @Published var lyrics: LyricsDocument?
    @Published var lyricsStatus = "Waiting for Music…"

    // Settings (persisted).
    @Published var overlayVisible: Bool { didSet { defaults.set(overlayVisible, forKey: Keys.overlayVisible) } }
    /// True while the overlay is being dragged (or ⌥ is held over it); shows the outline.
    @Published var dragging = false
    /// Whether macOS lets us intercept right-clicks (System Settings > Accessibility).
    @Published var accessibilityTrusted = false
    @Published var offset: TimeInterval { didSet { defaults.set(offset, forKey: Keys.offset) } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }
    @Published var lrclibEnabled: Bool { didSet { defaults.set(lrclibEnabled, forKey: Keys.lrclibEnabled) } }

    let clock = PlaybackClock()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let overlayVisible = "overlayVisible"
        static let offset = "offset"
        static let fontSize = "fontSize"
        static let lrclibEnabled = "lrclibEnabled"
    }

    init() {
        defaults.register(defaults: [
            Keys.overlayVisible: true,
            Keys.offset: 0.0,
            Keys.fontSize: 30.0,
            Keys.lrclibEnabled: true,
        ])
        overlayVisible = defaults.bool(forKey: Keys.overlayVisible)
        offset = defaults.double(forKey: Keys.offset)
        fontSize = defaults.double(forKey: Keys.fontSize)
        lrclibEnabled = defaults.bool(forKey: Keys.lrclibEnabled)
    }

    /// Whether the overlay should be on screen right now.
    var shouldShowOverlay: Bool {
        overlayVisible && track != nil && snapshot?.state != .stopped
    }
}
