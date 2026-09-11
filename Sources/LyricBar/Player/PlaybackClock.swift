import Foundation

/// Extrapolates the playback position between two polls of the player so the UI
/// can update at any frame rate. Thread-safe.
final class PlaybackClock {
    private let lock = NSLock()
    private var anchorPosition: TimeInterval = 0
    private var anchorTime = Date()
    private var playing = false

    /// Feed a fresh reading from the player.
    /// - position: seconds into the track, read at `time`.
    func sync(position: TimeInterval, at time: Date, playing: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let predicted = extrapolate(at: time)
        let drift = position - predicted
        if !self.playing || !playing || abs(drift) > 0.35 {
            // Play/pause transition or a seek: snap to the reported position.
            anchorPosition = position
        } else {
            // Small jitter from polling latency: absorb half of it.
            anchorPosition = predicted + drift * 0.5
        }
        anchorTime = time
        self.playing = playing
    }

    func position(at time: Date = Date()) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return extrapolate(at: time)
    }

    var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return playing
    }

    private func extrapolate(at time: Date) -> TimeInterval {
        guard playing else { return anchorPosition }
        return max(0, anchorPosition + time.timeIntervalSince(anchorTime))
    }
}
