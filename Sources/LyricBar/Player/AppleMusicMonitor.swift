import AppKit
import Foundation

/// Watches Music.app.
///
/// Two channels are combined:
/// 1. `com.apple.Music.playerInfo` distributed notifications, which Music posts on
///    play / pause / track change. They carry no position, so we poll right after.
/// 2. A 1 Hz AppleScript poll (3 Hz slower when paused) that reads the position
///    and the current track. AppleScript is only sent when Music is running,
///    because sending it to a non-running app would launch Music.
final class AppleMusicMonitor: PlayerMonitor {
    let name = "Apple Music"
    var onSnapshot: (@MainActor (PlayerSnapshot) -> Void)?

    private let bundleID = "com.apple.Music"
    private let queue = DispatchQueue(label: "dev.lyricbar.applemusic", qos: .userInitiated)
    private var script: NSAppleScript?
    private var timer: DispatchSourceTimer?
    private var observer: NSObjectProtocol?
    private var lastState: PlaybackState?
    private var running = false
    private var consecutiveFailures = 0
    private var compileFailed = false

    /// Returns a list so we get typed values back (no string parsing).
    /// (Avoid short identifiers like `st`: AppleScript reserves st/nd/rd/th for ordinals.)
    private static let source = """
    tell application "Music"
        set playerStateValue to player state
        if playerStateValue is stopped then return {"stopped", 0.0, "", "", "", 0.0, ""}
        set stateName to "playing"
        if playerStateValue is paused then set stateName to "paused"
        try
            set trk to current track
            return {stateName, player position, name of trk, artist of trk, album of trk, duration of trk, persistent ID of trk}
        on error
            return {stateName, player position, "", "", "", 0.0, ""}
        end try
    end tell
    """

    func start() {
        guard !running else { return }
        running = true
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: nil
        ) { [weak self] note in
            let state = (note.userInfo?["Player State"] as? String) ?? "?"
            let title = (note.userInfo?["Name"] as? String) ?? ""
            Log.info("Music notification: state=\(state) name=\(title)")
            // Music posts slightly before its scriptable state settles.
            self?.queue.asyncAfter(deadline: .now() + 0.15) { self?.poll() }
        }
        scheduleTimer(interval: 1.0)
        queue.async { self.poll() }
    }

    func stop() {
        running = false
        timer?.cancel()
        timer = nil
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    func refreshNow() {
        queue.async { self.poll() }
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    private var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Runs on `queue` only.
    private func poll() {
        guard running else { return }
        guard isMusicRunning else {
            emit(PlayerSnapshot(state: .stopped, position: 0, track: nil, sampledAt: Date(), playerName: name))
            return
        }
        if script == nil {
            guard !compileFailed else { return }
            let s = NSAppleScript(source: Self.source)
            var err: NSDictionary?
            if s?.compileAndReturnError(&err) == true {
                script = s
            } else {
                compileFailed = true
                Log.error("AppleScript compile failed: \(err ?? [:])")
                return
            }
        }

        let before = Date()
        var err: NSDictionary?
        guard let result = script?.executeAndReturnError(&err) else {
            consecutiveFailures += 1
            if consecutiveFailures == 1 || consecutiveFailures % 30 == 0 {
                let code = (err?[NSAppleScript.errorNumber] as? Int) ?? 0
                var hint = ""
                if code == -1743 { hint = " (Automation permission denied: allow LyricBar to control Music in System Settings > Privacy & Security > Automation)" }
                Log.warn("AppleScript failed (\(code))\(hint): \(err?[NSAppleScript.errorMessage] ?? "")")
            }
            return
        }
        consecutiveFailures = 0
        let after = Date()
        // The position was read somewhere during the round trip; use the midpoint.
        let sampledAt = before.addingTimeInterval(after.timeIntervalSince(before) / 2)

        guard result.numberOfItems >= 7 else {
            Log.warn("Unexpected AppleScript result: \(result)")
            return
        }
        let stateName = result.atIndex(1)?.stringValue ?? "stopped"
        let position = result.atIndex(2)?.doubleValue ?? 0
        let title = result.atIndex(3)?.stringValue ?? ""
        let artist = result.atIndex(4)?.stringValue ?? ""
        let album = result.atIndex(5)?.stringValue ?? ""
        let duration = result.atIndex(6)?.doubleValue ?? 0
        let pid = result.atIndex(7)?.stringValue ?? ""

        let state = PlaybackState(rawValue: stateName) ?? .playing
        let track: TrackInfo? = (state == .stopped || title.isEmpty)
            ? nil
            : TrackInfo(id: pid, title: title, artist: artist, album: album, duration: duration)
        emit(PlayerSnapshot(state: state, position: position, track: track, sampledAt: sampledAt, playerName: name))
    }

    private func emit(_ snapshot: PlayerSnapshot) {
        if snapshot.state != lastState {
            lastState = snapshot.state
            scheduleTimer(interval: snapshot.state == .playing ? 1.0 : 3.0)
        }
        Task { @MainActor [onSnapshot] in
            onSnapshot?(snapshot)
        }
    }
}
