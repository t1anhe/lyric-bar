import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var monitor: PlayerMonitor?
    private var resolver: LyricsResolver?
    private var overlay: OverlayWindowController?
    private var statusBar: StatusBarController?
    private var lyricsTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.info("LyricBar \(version) starting")

        let store = LyricsStore()
        resolver = LyricsResolver(providers: [
            AppleMusicCacheProvider(store: store),
            // UserDefaults is thread-safe, so the background provider can read the
            // setting directly (AppState keeps the key up to date).
            LRCLIBProvider(store: store, isEnabled: { UserDefaults.standard.bool(forKey: "lrclibEnabled") }),
        ])

        overlay = OverlayWindowController(state: state)
        statusBar = StatusBarController(state: state, reloadLyrics: { [weak self] in self?.reloadLyrics() })

        state.$overlayVisible.dropFirst().sink { [weak self] _ in self?.overlay?.updateVisibility() }.store(in: &cancellables)
        state.$locked.sink { [weak self] locked in self?.overlay?.setLocked(locked) }.store(in: &cancellables)
        state.$fontSize.sink { [weak self] size in self?.overlay?.setFontSize(size) }.store(in: &cancellables)

        let monitor = AppleMusicMonitor()
        monitor.onSnapshot = { [weak self] snapshot in self?.handle(snapshot) }
        self.monitor = monitor
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        Log.info("LyricBar stopped")
    }

    private func handle(_ snapshot: PlayerSnapshot) {
        let previousKey = state.track?.contentKey
        if snapshot.state != state.snapshot?.state {
            Log.info("Player state: \(snapshot.state.rawValue) at \(String(format: "%.2f", snapshot.position))s")
        }
        state.snapshot = snapshot
        state.clock.sync(position: snapshot.position, at: snapshot.sampledAt, playing: snapshot.state == .playing)

        if snapshot.track?.contentKey != previousKey {
            state.track = snapshot.track
            state.lyrics = nil
            lyricsTask?.cancel()
            if let track = snapshot.track {
                Log.info("Now playing: \"\(track.title)\" by \(track.artist) [\(Int(track.duration))s]")
                fetchLyrics(for: track)
            } else {
                state.lyricsStatus = "Nothing playing"
            }
        }
        overlay?.updateVisibility()
    }

    private func fetchLyrics(for track: TrackInfo) {
        guard let resolver else { return }
        state.lyricsStatus = "Searching…"
        lyricsTask = Task { [weak self] in
            let doc = await resolver.resolve(track)
            guard !Task.isCancelled, let self, self.state.track?.contentKey == track.contentKey else { return }
            self.state.lyrics = doc
            if let doc {
                self.state.lyricsStatus = "\(doc.lines.count) lines · \(doc.source) · \(doc.timing.rawValue) timing"
            } else {
                self.state.lyricsStatus = "No lyrics found"
            }
        }
    }

    func reloadLyrics() {
        guard let track = state.track else { return }
        lyricsTask?.cancel()
        state.lyrics = nil
        fetchLyrics(for: track)
    }
}
