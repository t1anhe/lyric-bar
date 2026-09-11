import Foundation

/// Optional fallback: the free, open LRCLIB database (https://lrclib.net).
/// Only used when the first-party source has nothing.
final class LRCLIBProvider: LyricsProvider {
    let name = "LRCLIB"
    private let isEnabled: () -> Bool
    private let store: LyricsStore?
    private let session: URLSession

    init(store: LyricsStore?, isEnabled: @escaping () -> Bool) {
        self.store = store
        self.isEnabled = isEnabled
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "LyricBar/0.1 (https://github.com/lyric-bar)"]
        session = URLSession(configuration: config)
    }

    func lyrics(for track: TrackInfo) async -> LyricsDocument? {
        guard isEnabled() else { return nil }
        if let saved = store?.load(for: track), saved.format == .lrc,
           let doc = LRCParser.parse(saved.text, source: name) {
            return doc
        }
        guard !track.title.isEmpty else { return nil }

        var lrc = await exactLookup(track)
        if lrc == nil, !Task.isCancelled { lrc = await searchLookup(track) }
        guard let lrc else { return nil }
        store?.save(lrc, format: .lrc, for: track)
        return LRCParser.parse(lrc, source: name)
    }

    private func exactLookup(_ track: TrackInfo) async -> String? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if !track.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: track.album)) }
        if track.duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))) }
        comps.queryItems = items
        guard let json = await getJSON(comps.url!) as? [String: Any] else { return nil }
        return json["syncedLyrics"] as? String
    }

    private func searchLookup(_ track: TrackInfo) async -> String? {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        guard let results = await getJSON(comps.url!) as? [[String: Any]] else { return nil }
        let candidates = results.compactMap { r -> (String, Double)? in
            guard let synced = r["syncedLyrics"] as? String, !synced.isEmpty else { return nil }
            let d = (r["duration"] as? Double) ?? 0
            return (synced, track.duration > 0 && d > 0 ? abs(d - track.duration) : 0)
        }
        guard let best = candidates.min(by: { $0.1 < $1.1 }), best.1 <= 5 else { return nil }
        return best.0
    }

    private func getJSON(_ url: URL) async -> Any? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard http.statusCode == 200 else {
                if http.statusCode != 404 { Log.warn("LRCLIB \(http.statusCode) for \(url)") }
                return nil
            }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            Log.warn("LRCLIB request failed: \(error.localizedDescription)")
            return nil
        }
    }
}
