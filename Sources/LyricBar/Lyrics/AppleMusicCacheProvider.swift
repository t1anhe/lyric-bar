import Foundation

/// Reads the lyrics Music.app itself downloaded.
///
/// Every time Music plays a track it requests
/// `amp-api.music.apple.com/v1/catalog/<storefront>/songs/<id>?include=syllable-lyrics…`
/// and its URL cache keeps the JSON response on disk under
/// `~/Library/Caches/com.apple.Music/fsCachedData/<UUID>`. The response embeds the
/// TTML lyrics (word timing, translations). We scan that directory for a response
/// whose song matches the current track. Nothing is sent over the network.
final class AppleMusicCacheProvider: LyricsProvider {
    let name = "Apple Music"

    private let directory: URL
    private let store: LyricsStore?
    /// How long to keep looking after a track starts (Music needs a moment to fetch).
    private let maxWait: TimeInterval
    private let lock = NSLock()
    private var index: [String: CacheEntry] = [:]

    private struct SongMeta {
        let id: String
        let title: String
        let artist: String
        let album: String
        let durationMs: Int
        let hasLyrics: Bool
    }

    private struct CacheEntry {
        let mtime: Date
        let size: Int
        let songs: [SongMeta]
    }

    init(store: LyricsStore?, maxWait: TimeInterval = 25) {
        self.store = store
        self.maxWait = maxWait
        directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.apple.Music/fsCachedData", isDirectory: true)
    }

    func lyrics(for track: TrackInfo) async -> LyricsDocument? {
        if let saved = store?.load(for: track), saved.format == .ttml,
           let doc = TTMLParser.parse(saved.text, source: name) {
            return doc
        }

        let deadline = Date().addingTimeInterval(maxWait)
        var attempt = 0
        while true {
            if Task.isCancelled { return nil }
            switch scan(for: track) {
            case .found(let songID, let ttml):
                if let doc = TTMLParser.parse(ttml, source: name) {
                    store?.save(ttml, format: .ttml, for: track)
                    return doc
                }
                Log.warn("Cache hit for song \(songID) but TTML did not parse")
                return nil
            case .noLyrics(let songID):
                Log.info("Apple Music cache: song \(songID) has no synced lyrics")
                return nil
            case .notFound:
                break
            }
            attempt += 1
            let now = Date()
            guard now < deadline else { return nil }
            let delay = min(attempt < 5 ? 1.0 : 2.0, deadline.timeIntervalSince(now))
            try? await Task.sleep(nanoseconds: UInt64(max(0.05, delay) * 1_000_000_000))
        }
    }

    // MARK: Scanning

    private enum ScanResult {
        case found(songID: String, ttml: String)
        /// Music fetched this track, but Apple has no synced lyrics for it.
        case noLyrics(songID: String)
        case notFound
    }

    /// How confident we are that a cached song is the current track.
    private enum MatchKind: Int, Comparable {
        /// Same title and duration. Titles can differ between the library and the
        /// catalog response (e.g. "就是现在" vs "Now Is the Time" when Music runs
        /// in English), so this is not the only rule.
        case title = 3
        /// Same duration and the file was written after this track started:
        /// Music requests the lyrics of a track right after it starts playing.
        case timing = 2
        /// Same duration and no other cached song has that duration.
        case uniqueDuration = 1

        static func < (a: MatchKind, b: MatchKind) -> Bool { a.rawValue < b.rawValue }
    }

    private func scan(for track: TrackInfo) -> ScanResult {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .notFound
        }

        struct Candidate {
            let kind: MatchKind
            let mtime: Date
            let url: URL
            let song: SongMeta
        }
        var candidates: [Candidate] = []
        var sameDurationSongIDs = Set<String>()

        lock.lock()
        defer { lock.unlock() }
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? 0
            let key = url.lastPathComponent
            let entry: CacheEntry
            if let cached = index[key], cached.mtime == mtime, cached.size == size {
                entry = cached
            } else {
                entry = CacheEntry(mtime: mtime, size: size, songs: Self.parseSongs(at: url))
                index[key] = entry
            }
            for song in entry.songs {
                if Self.durationDelta(song, track) <= 1.0 { sameDurationSongIDs.insert(song.id) }
                if let kind = Self.classify(song, track, fileModifiedAt: mtime) {
                    candidates.append(Candidate(kind: kind, mtime: mtime, url: url, song: song))
                }
            }
        }
        // Drop index entries for files that disappeared.
        let present = Set(urls.map(\.lastPathComponent))
        index = index.filter { present.contains($0.key) }

        // A duration-only match is only trusted when nothing else has that duration.
        if sameDurationSongIDs.count != 1 {
            candidates.removeAll { $0.kind == .uniqueDuration }
        }
        // Best confidence first, then the closest duration, then the newest file.
        guard let hit = candidates.max(by: { a, b in
            if a.kind != b.kind { return a.kind < b.kind }
            let da = Self.durationDelta(a.song, track), db = Self.durationDelta(b.song, track)
            if abs(da - db) > 0.05 { return da > db }
            return a.mtime < b.mtime
        }) else { return .notFound }

        guard hit.song.hasLyrics else { return .noLyrics(songID: hit.song.id) }
        guard let ttml = Self.extractTTML(at: hit.url, songID: hit.song.id) else { return .notFound }
        Log.info("Apple Music cache: matched song \(hit.song.id) \"\(hit.song.title)\" by \(hit.song.artist) via \(hit.kind) in \(hit.url.lastPathComponent)")
        return .found(songID: hit.song.id, ttml: ttml)
    }

    private static func durationDelta(_ song: SongMeta, _ track: TrackInfo) -> TimeInterval {
        guard track.duration > 0, song.durationMs > 0 else { return .infinity }
        return abs(track.duration - Double(song.durationMs) / 1000)
    }

    private static func classify(_ song: SongMeta, _ track: TrackInfo, fileModifiedAt mtime: Date) -> MatchKind? {
        let delta = durationDelta(song, track)
        let title = TextNormalizer.normalize(track.title)
        let sameTitle = !title.isEmpty && title == TextNormalizer.normalize(song.title)
        let sameArtist = TextNormalizer.normalize(track.artist) == TextNormalizer.normalize(song.artist)

        if sameTitle {
            if delta <= 2.5 { return .title }
            if delta == .infinity, sameArtist { return .title }
        }
        if delta <= 1.5, let started = track.playbackStartedAt,
           mtime >= started.addingTimeInterval(-120), mtime <= Date().addingTimeInterval(5) {
            return .timing
        }
        if delta <= 1.0 { return .uniqueDuration }
        return nil
    }

    private static func songsArray(at url: URL) -> [[String: Any]]? {
        guard let data = try? Data(contentsOf: url), data.count < 4_000_000 else { return nil }
        // Cheap pre-check before JSON parsing: every lyrics response mentions the relationship.
        guard data.range(of: Data("syllable-lyrics".utf8)) != nil else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return nil }
        return items
    }

    private static func parseSongs(at url: URL) -> [SongMeta] {
        guard let items = songsArray(at: url) else { return [] }
        return items.compactMap { item in
            guard (item["type"] as? String) == "songs",
                  let id = item["id"] as? String,
                  let attrs = item["attributes"] as? [String: Any] else { return nil }
            return SongMeta(
                id: id,
                title: attrs["name"] as? String ?? "",
                artist: attrs["artistName"] as? String ?? "",
                album: attrs["albumName"] as? String ?? "",
                durationMs: attrs["durationInMillis"] as? Int ?? 0,
                hasLyrics: ttml(in: item) != nil
            )
        }
    }

    private static func extractTTML(at url: URL, songID: String) -> String? {
        guard let items = songsArray(at: url) else { return nil }
        for item in items where (item["id"] as? String) == songID {
            if let t = ttml(in: item) { return t }
        }
        return nil
    }

    private static func ttml(in item: [String: Any]) -> String? {
        guard let rel = item["relationships"] as? [String: Any],
              let lyrics = rel["syllable-lyrics"] as? [String: Any] ?? rel["lyrics"] as? [String: Any],
              let entries = lyrics["data"] as? [[String: Any]] else { return nil }
        for entry in entries {
            guard let attrs = entry["attributes"] as? [String: Any] else { continue }
            if let t = attrs["ttmlLocalizations"] as? String, !t.isEmpty { return t }
            if let t = attrs["ttml"] as? String, !t.isEmpty { return t }
        }
        return nil
    }
}
