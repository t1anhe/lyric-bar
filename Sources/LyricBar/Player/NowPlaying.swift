import Foundation

enum PlaybackState: String {
    case stopped, paused, playing
}

/// What we know about the track that is currently loaded in the player.
struct TrackInfo: Equatable {
    /// Player-specific identifier (Music's persistent ID). May be empty.
    var id: String
    var title: String
    var artist: String
    var album: String
    /// Seconds. 0 when unknown.
    var duration: TimeInterval
    /// When this track started playing (host time), estimated from the playback
    /// position at the moment the track was first seen. Used to pair the track
    /// with the lyrics file Music writes right after a track starts.
    var playbackStartedAt: Date? = nil

    /// Stable key used to detect track changes and to cache lyrics.
    /// Built from the content rather than the player ID so the same song
    /// resolves to the same lyrics whether it is played from the library or from
    /// a streaming playlist.
    var contentKey: String {
        let t = TextNormalizer.normalize(title)
        let a = TextNormalizer.normalize(artist)
        return "\(t)|\(a)|\(Int(duration.rounded()))"
    }
}

/// One reading of the player state, taken at `sampledAt` (host time).
struct PlayerSnapshot: Equatable {
    var state: PlaybackState
    var position: TimeInterval
    var track: TrackInfo?
    var sampledAt: Date
    var playerName: String
}

enum TextNormalizer {
    /// Lowercases, strips accents and punctuation, collapses whitespace.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var out = ""
        var lastWasSpace = true
        for ch in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) {
                out.unicodeScalars.append(ch)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
