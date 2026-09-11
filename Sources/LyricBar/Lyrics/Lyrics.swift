import Foundation

struct LyricWord: Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

struct LyricLine: Identifiable, Equatable {
    /// Index within the document.
    let id: Int
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    /// Word-level timing when available, otherwise empty.
    var words: [LyricWord]
    var translation: String?
    /// Singer identifier for duets (TTML `ttm:agent`).
    var agent: String?
}

enum LyricsTiming: String {
    case word, line, none
}

struct LyricsDocument: Equatable {
    /// Sorted by `start`.
    var lines: [LyricLine]
    var timing: LyricsTiming
    /// Provider that produced the document, for display.
    var source: String
    var language: String?

    /// Index of the line that should be shown at time `t`: the last line whose
    /// start is <= t. `nil` before the first line.
    func index(at t: TimeInterval) -> Int? {
        var lo = 0
        var hi = lines.count - 1
        var answer: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= t {
                answer = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return answer
    }
}
