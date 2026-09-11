import Foundation

/// A source of lyrics. Implementations must be safe to call from any task and
/// should honour `Task.isCancelled` if they wait for anything.
protocol LyricsProvider: AnyObject {
    var name: String { get }
    func lyrics(for track: TrackInfo) async -> LyricsDocument?
}

/// Asks each provider in order and returns the first document found.
final class LyricsResolver {
    let providers: [LyricsProvider]

    init(providers: [LyricsProvider]) {
        self.providers = providers
    }

    func resolve(_ track: TrackInfo, progress: ((String) -> Void)? = nil) async -> LyricsDocument? {
        for provider in providers {
            if Task.isCancelled { return nil }
            progress?("Searching \(provider.name)…")
            let started = Date()
            if let doc = await provider.lyrics(for: track) {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                Log.info("Lyrics from \(provider.name): \(doc.lines.count) lines, timing=\(doc.timing.rawValue), \(ms) ms")
                return doc
            }
        }
        Log.info("No lyrics found for \"\(track.title)\" by \(track.artist)")
        return nil
    }
}
