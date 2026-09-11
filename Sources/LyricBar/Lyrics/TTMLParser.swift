import Foundation

/// Parses Apple Music's TTML lyrics, the format behind the `syllable-lyrics`
/// relationship of the Apple Music API. Structure (namespaces omitted):
///
///     <tt itunes:timing="Word|Line|None" xml:lang="en">
///       <head><metadata>
///         <iTunesMetadata>
///           <translations><translation type="subtitle|replacement" xml:lang="zh-Hans">
///             <text for="L1">…</text>
///           </translation></translations>
///         </iTunesMetadata>
///       </metadata></head>
///       <body><div itunes:songPart="Verse">
///         <p begin="9.173" end="11.383" itunes:key="L1" ttm:agent="v1">
///           <span begin="9.173" end="9.453">word</span> <span …>word</span>
///           <span ttm:role="x-bg"><span …>(background vocal)</span></span>
///         </p>
///       </div></body>
///     </tt>
///
/// `translation type="subtitle"` is a real translation; `type="replacement"` is
/// the same language in another script (e.g. Traditional -> Simplified Chinese)
/// and is used instead of the original text.
final class TTMLParser: NSObject, XMLParserDelegate {
    static func parse(_ ttml: String, source: String) -> LyricsDocument? {
        guard let data = ttml.data(using: .utf8) else { return nil }
        let delegate = TTMLParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        let ok = parser.parse()
        if !ok, delegate.lines.isEmpty {
            Log.warn("TTML parse failed: \(parser.parserError?.localizedDescription ?? "?")")
            return nil
        }
        return delegate.document(source: source)
    }

    private struct RawLine {
        var key: String?
        var agent: String?
        var start: TimeInterval
        var end: TimeInterval
        var text = ""
        var words: [LyricWord] = []
    }

    private var timing: LyricsTiming = .line
    private var language: String?
    private var lines: [RawLine] = []
    /// translation type -> (line key -> text)
    private var translations: [String: [String: String]] = [:]

    // Parser state.
    private var inBody = false
    private var current: RawLine?
    private var currentWord: LyricWord?
    private var backgroundDepth = 0
    private var inTranslations = false
    private var currentTranslationType: String?
    private var currentTextKey: String?
    private var textBuffer = ""

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes attrs: [String: String]) {
        switch name {
        case "tt":
            switch attrs["itunes:timing"]?.lowercased() {
            case "word": timing = .word
            case "line": timing = .line
            case "none": timing = .none
            default: timing = .line
            }
            language = attrs["xml:lang"]
        case "body":
            inBody = true
        case "translations":
            inTranslations = true
        case "translation" where inTranslations:
            let type = attrs["type"] ?? "subtitle"
            currentTranslationType = type
            if translations[type] == nil { translations[type] = [:] }
        case "text" where inTranslations:
            currentTextKey = attrs["for"]
            textBuffer = ""
        case "p" where inBody:
            current = RawLine(key: attrs["itunes:key"], agent: attrs["ttm:agent"],
                              start: Self.time(attrs["begin"]) ?? 0, end: Self.time(attrs["end"]) ?? 0)
            backgroundDepth = 0
            currentWord = nil
        case "span" where inBody && current != nil:
            if backgroundDepth > 0 {
                backgroundDepth += 1
            } else if attrs["ttm:role"] == "x-bg" {
                backgroundDepth = 1
            } else if let b = Self.time(attrs["begin"]), let e = Self.time(attrs["end"]) {
                currentWord = LyricWord(start: b, end: e, text: "")
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTranslations {
            if currentTextKey != nil { textBuffer += string }
            return
        }
        guard inBody, current != nil, backgroundDepth == 0 else { return }
        current?.text += string
        currentWord?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "span" where inBody && current != nil:
            if backgroundDepth > 0 {
                backgroundDepth -= 1
            } else if var word = currentWord {
                word.text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !word.text.isEmpty { current?.words.append(word) }
                currentWord = nil
            }
        case "p" where inBody:
            if let line = current { lines.append(line) }
            current = nil
        case "text" where inTranslations:
            if let key = currentTextKey, let type = currentTranslationType {
                translations[type]?[key] = Self.collapseWhitespace(textBuffer)
            }
            currentTextKey = nil
        case "translation":
            currentTranslationType = nil
        case "translations":
            inTranslations = false
        case "body":
            inBody = false
        default:
            break
        }
    }

    // MARK: Output

    private func document(source: String) -> LyricsDocument? {
        let replacement = translations["replacement"]
        let subtitle = translations["subtitle"]
        let sorted = lines.enumerated().sorted { a, b in
            a.element.start == b.element.start ? a.offset < b.offset : a.element.start < b.element.start
        }.map(\.element)

        var out: [LyricLine] = []
        for (i, raw) in sorted.enumerated() {
            var text = Self.collapseWhitespace(raw.text)
            if let key = raw.key, let r = replacement?[key], !r.isEmpty { text = r }
            guard !text.isEmpty else { continue }
            var end = raw.end
            if end <= raw.start {
                end = i + 1 < sorted.count ? sorted[i + 1].start : raw.start + 5
            }
            out.append(LyricLine(id: out.count, start: raw.start, end: end, text: text, words: raw.words,
                                 translation: raw.key.flatMap { subtitle?[$0] }, agent: raw.agent))
        }
        guard !out.isEmpty else { return nil }
        return LyricsDocument(lines: out, timing: timing, source: source, language: language)
    }

    // MARK: Helpers

    /// TTML clock times: "9.173", "1:02.5", "1:02:03.4", "1500ms", "12.5s".
    static func time(_ raw: String?) -> TimeInterval? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasSuffix("ms") { return Double(s.dropLast(2)).map { $0 / 1000 } }
        if s.hasSuffix("s") { s = String(s.dropLast()) }
        var total = 0.0
        for part in s.split(separator: ":") {
            guard let v = Double(part) else { return nil }
            total = total * 60 + v
        }
        return total
    }

    static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}
