import Foundation

/// Parses LRC files: `[mm:ss.xx]text`, several tags per line allowed, plus the
/// "enhanced" `<mm:ss.xx>word` form for word timing.
enum LRCParser {
    private static let lineTag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>"#)

    static func parse(_ lrc: String, source: String) -> LyricsDocument? {
        var entries: [(start: TimeInterval, text: String, words: [LyricWord])] = []
        var hasWords = false

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let ns = line as NSString
            let tags = lineTag.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let first = tags.first, first.range.location == 0 else { continue }

            // Tags are contiguous at the start; the text follows the last one.
            var textStart = first.range.location + first.range.length
            var times: [TimeInterval] = [seconds(ns, first)]
            for tag in tags.dropFirst() {
                guard tag.range.location == textStart else { break }
                times.append(seconds(ns, tag))
                textStart = tag.range.location + tag.range.length
            }
            let rest = ns.substring(from: textStart)
            let (text, words) = parseWords(rest)
            if !words.isEmpty { hasWords = true }
            for t in times { entries.append((t, text, words)) }
        }

        entries.sort { $0.start < $1.start }
        var lines: [LyricLine] = []
        for (i, e) in entries.enumerated() {
            let text = e.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let end = i + 1 < entries.count ? entries[i + 1].start : e.start + 5
            lines.append(LyricLine(id: lines.count, start: e.start, end: end, text: text, words: e.words,
                                   translation: nil, agent: nil))
        }
        guard !lines.isEmpty else { return nil }
        return LyricsDocument(lines: lines, timing: hasWords ? .word : .line, source: source, language: nil)
    }

    private static func seconds(_ ns: NSString, _ m: NSTextCheckingResult) -> TimeInterval {
        let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
        let secs = Double(ns.substring(with: m.range(at: 2))) ?? 0
        var frac = 0.0
        if m.range(at: 3).location != NSNotFound {
            frac = Double("0." + ns.substring(with: m.range(at: 3))) ?? 0
        }
        return minutes * 60 + secs + frac
    }

    private static func parseWords(_ text: String) -> (String, [LyricWord]) {
        let ns = text as NSString
        let tags = wordTag.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !tags.isEmpty else { return (text, []) }
        var words: [LyricWord] = []
        var plain = ns.substring(to: tags[0].range.location)
        for (i, tag) in tags.enumerated() {
            let start = seconds(ns, tag)
            let from = tag.range.location + tag.range.length
            let to = i + 1 < tags.count ? tags[i + 1].range.location : ns.length
            let word = ns.substring(with: NSRange(location: from, length: to - from))
            plain += word
            let end = i + 1 < tags.count ? seconds(ns, tags[i + 1]) : start + 1
            let trimmed = word.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { words.append(LyricWord(start: start, end: end, text: trimmed)) }
        }
        return (plain, words)
    }
}
