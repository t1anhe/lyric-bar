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
    /// Move mode: the overlay catches clicks and can be dragged. Otherwise it is
    /// click-through and fades while the mouse is over it.
    @Published var movable: Bool { didSet { defaults.set(movable, forKey: Keys.movable) } }
    @Published var offset: TimeInterval { didSet { defaults.set(offset, forKey: Keys.offset) } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }
    @Published var lrclibEnabled: Bool { didSet { defaults.set(lrclibEnabled, forKey: Keys.lrclibEnabled) } }

    let clock = PlaybackClock()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let overlayVisible = "overlayVisible"
        static let movable = "overlayMovable"
        static let offset = "offset"
        static let fontSize = "fontSize"
        static let lrclibEnabled = "lrclibEnabled"
    }

    init() {
        defaults.register(defaults: [
            Keys.overlayVisible: true,
            Keys.movable: false,
            Keys.offset: 0.0,
            Keys.fontSize: 30.0,
            Keys.lrclibEnabled: true,
        ])
        overlayVisible = defaults.bool(forKey: Keys.overlayVisible)
        movable = defaults.bool(forKey: Keys.movable)
        offset = defaults.double(forKey: Keys.offset)
        fontSize = defaults.double(forKey: Keys.fontSize)
        lrclibEnabled = defaults.bool(forKey: Keys.lrclibEnabled)
    }

    /// Whether the overlay should be on screen right now.
    var shouldShowOverlay: Bool {
        overlayVisible && track != nil && snapshot?.state != .stopped
    }
}
