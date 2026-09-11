import AppKit
import Foundation

/// Text measurements for one lyric line: the font size that fits the available
/// width and the horizontal extent of every timed word, so the karaoke fill can
/// stop exactly at the word (or the fraction of the word) being sung.
struct LineMetrics {
    struct WordSpan {
        let start: TimeInterval
        let end: TimeInterval
        let x0: CGFloat
        let x1: CGFloat
    }

    let fontSize: CGFloat
    /// Width of the whole line at `fontSize`.
    let width: CGFloat
    /// Empty when the words could not be located in the text (line timing is used then).
    let wordSpans: [WordSpan]

    static func measure(line: LyricLine, baseFontSize: CGFloat, maxWidth: CGFloat) -> LineMetrics {
        func width(_ text: String, _ size: CGFloat) -> CGFloat {
            let font = NSFont.systemFont(ofSize: size, weight: .bold)
            return (text as NSString).size(withAttributes: [.font: font]).width
        }

        var size = baseFontSize
        var full = width(line.text, size)
        if full > maxWidth, full > 0 {
            // Same rule as SwiftUI's minimumScaleFactor(0.5), but explicit so the
            // word positions below are measured with the size actually drawn.
            size = max(baseFontSize * 0.5, baseFontSize * maxWidth / full)
            full = width(line.text, size)
        }

        // Words appear in order inside the line text; locate each one after the previous.
        var spans: [WordSpan] = []
        var cursor = line.text.startIndex
        for word in line.words {
            guard let range = line.text.range(of: word.text, range: cursor..<line.text.endIndex) else {
                spans = []
                break
            }
            let x0 = width(String(line.text[..<range.lowerBound]), size)
            let x1 = width(String(line.text[..<range.upperBound]), size)
            spans.append(WordSpan(start: word.start, end: word.end, x0: x0, x1: x1))
            cursor = range.upperBound
        }
        return LineMetrics(fontSize: size, width: full, wordSpans: spans)
    }

    /// How far (in points from the leading edge) the line has been sung at `t`.
    func progressX(at t: TimeInterval, line: LyricLine) -> CGFloat {
        if wordSpans.isEmpty {
            guard line.end > line.start else { return 0 }
            let fraction = min(1, max(0, (t - line.start) / (line.end - line.start)))
            return width * fraction
        }
        var x: CGFloat = 0
        for span in wordSpans {
            if t >= span.end {
                x = span.x1
            } else if t >= span.start {
                let fraction = (t - span.start) / max(0.001, span.end - span.start)
                return span.x0 + (span.x1 - span.x0) * fraction
            } else {
                break
            }
        }
        return x
    }
}

/// Measuring text is not free; the overlay redraws 30 times a second, so cache
/// the metrics per line, font size and width. Main thread only.
@MainActor
final class LineMetricsCache {
    static let shared = LineMetricsCache()
    private var cache: [String: LineMetrics] = [:]

    func metrics(for line: LyricLine, baseFontSize: CGFloat, maxWidth: CGFloat) -> LineMetrics {
        let key = "\(line.id)|\(line.text.hashValue)|\(baseFontSize)|\(Int(maxWidth))"
        if let cached = cache[key] { return cached }
        if cache.count > 400 { cache.removeAll() }
        let metrics = LineMetrics.measure(line: line, baseFontSize: baseFontSize, maxWidth: maxWidth)
        cache[key] = metrics
        return metrics
    }
}
