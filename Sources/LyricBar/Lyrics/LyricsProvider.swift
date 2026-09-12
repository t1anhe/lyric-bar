import Foundation

/// A source of lyrics. Implementations must be safe to call from any task and
/// should honour `Task.isCancelled` if they wait for anything.
protocol LyricsProvider: AnyObject {
    var name: String { get }
    func lyrics(for track: TrackInfo) async -> LyricsDocument?
}

/// Runs every provider at the same time. Providers are listed in order of
/// preference: a result from an earlier provider replaces one from a later
/// provider, but a later provider's result is shown right away if it comes
/// first (LRCLIB answers in a second; the Apple Music cache may need Music to
/// fetch the lyrics first).
final class LyricsResolver {
    let providers: [LyricsProvider]

    init(providers: [LyricsProvider]) {
        self.providers = providers
    }

    /// Calls `onDocument` each time a better document arrives, then returns the
    /// best one (nil if nothing was found).
    func resolve(_ track: TrackInfo, onDocument: @escaping (LyricsDocument) -> Void) async -> LyricsDocument? {
        let started = Date()
        var best: (rank: Int, doc: LyricsDocument)?
        await withTaskGroup(of: (Int, LyricsDocument?).self) { group in
            for (rank, provider) in providers.enumerated() {
                group.addTask { (rank, await provider.lyrics(for: track)) }
            }
            for await (rank, doc) in group {
                guard let doc, !Task.isCancelled else { continue }
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                Log.info("Lyrics from \(providers[rank].name): \(doc.lines.count) lines, timing=\(doc.timing.rawValue), \(ms) ms")
                if best == nil || rank < best!.rank {
                    best = (rank, doc)
                    onDocument(doc)
                }
            }
        }
        if best == nil, !Task.isCancelled {
            Log.info("No lyrics found for \"\(track.title)\" by \(track.artist)")
        }
        return best?.doc
    }
}
