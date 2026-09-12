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
        state.$fontSize.sink { [weak self] size in self?.overlay?.setFontSize(size) }.store(in: &cancellables)

        let monitor = AppleMusicMonitor()
        monitor.onSnapshot = { [weak self] snapshot in self?.handle(snapshot) }
        self.monitor = monitor
        monitor.start()
        overlay?.setUpRightDrag()
        installDebugChannel()
    }

    /// `dev.lyricbar.debug` distributed notifications let a terminal poke the
    /// running app (which holds the Automation permission) while developing.
    private func installDebugChannel() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("dev.lyricbar.debug"), object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let command = note.object as? String else { return }
                Log.info("debug command: \(command)")
                switch command {
                case "reload":
                    self.reloadLyrics()
                case let script where script.hasPrefix("script:"):
                    (self.monitor as? AppleMusicMonitor)?.debugRun(script: String(script.dropFirst("script:".count)))
                case let move where move.hasPrefix("move:"):
                    let parts = move.dropFirst("move:".count).split(separator: ",").compactMap { Double($0) }
                    if parts.count == 2 { self.overlay?.debugMove(to: NSPoint(x: parts[0], y: parts[1])) }
                default:
                    Log.warn("unknown debug command")
                }
            }
        }
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
            var track = snapshot.track
            track?.playbackStartedAt = snapshot.sampledAt.addingTimeInterval(-snapshot.position)
            state.track = track
            state.lyrics = nil
            lyricsTask?.cancel()
            if let track {
                Log.info("Now playing: \"\(track.title)\" by \(track.artist) [\(Int(track.duration))s], position \(String(format: "%.1f", snapshot.position))s")
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
            let doc = await resolver.resolve(track, onDocument: { doc in
                Task { @MainActor [weak self] in
                    guard let self, self.state.track?.contentKey == track.contentKey else { return }
                    self.state.lyrics = doc
                    self.state.lyricsStatus = "\(doc.lines.count) lines · \(doc.source) · \(doc.timing.rawValue) timing"
                }
            })
            guard !Task.isCancelled, let self, self.state.track?.contentKey == track.contentKey else { return }
            if doc == nil {
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
