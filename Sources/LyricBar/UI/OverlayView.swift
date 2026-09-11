import SwiftUI

/// The floating lyrics. Fully transparent background; lines scroll upward: the
/// finished line slides up and fades out, the next line moves up into the main
/// slot, and the line after it slides in from below. The current line is
/// filled with colour word by word as it is sung.
struct OverlayView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let position = state.clock.position(at: context.date) + state.offset
            content(at: position)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // In move mode the window must catch clicks to be draggable; macOS lets
        // clicks fall through fully transparent pixels, so keep an invisible fill.
        .background(Color.black.opacity(state.movable ? 0.01 : 0))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(state.movable ? 0.35 : 0), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    @ViewBuilder
    private func content(at position: TimeInterval) -> some View {
        if let doc = state.lyrics {
            LyricsScroller(lines: doc.lines, index: doc.index(at: position) ?? -1, position: position, fontSize: state.fontSize)
        } else if let track = state.track {
            StatusLines(title: "\(track.title) — \(track.artist)", subtitle: state.lyricsStatus, fontSize: state.fontSize)
        } else {
            StatusLines(title: "LyricBar", subtitle: state.lyricsStatus, fontSize: state.fontSize)
        }
    }
}

/// Geometry shared by the view and the window (height follows the font size).
enum OverlayLayout {
    static func panelHeight(fontSize: Double) -> CGFloat { CGFloat(fontSize) * 4.3 }
    static func currentLineCenter(fontSize: Double) -> CGFloat { CGFloat(fontSize) * 1.8 }
    static func slotGap(fontSize: Double) -> CGFloat { CGFloat(fontSize) * 1.65 }
    static let secondaryScale: CGFloat = 0.6
    static let horizontalPadding: CGFloat = 24
}

enum OverlayStyle {
    /// Colour of the sung part of the current line: a rainbow across the whole
    /// line, revealed as the fill advances. Slightly desaturated and fully
    /// bright so every hue stays readable over the text shadow.
    static let highlight = LinearGradient(
        colors: [0.0, 0.08, 0.16, 0.33, 0.5, 0.62, 0.76, 0.88, 1.0].map {
            Color(hue: $0, saturation: 0.8, brightness: 1.0)
        },
        startPoint: .leading, endPoint: .trailing
    )
}

private struct LyricsScroller: View {
    let lines: [LyricLine]
    /// Current line, or -1 before the first line.
    let index: Int
    let position: TimeInterval
    let fontSize: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let textWidth = width - OverlayLayout.horizontalPadding * 2
            let currentY = OverlayLayout.currentLineCenter(fontSize: fontSize)
            let gap = OverlayLayout.slotGap(fontSize: fontSize)
            // Previous line (sliding out), current, next, and the one after (sliding in).
            let lower = max(0, index - 1)
            let upper = min(lines.count - 1, index + 2)
            ZStack {
                if index < 0 {
                    LyricText(text: "♪", fontSize: fontSize)
                        .frame(width: width)
                        .opacity(0.8)
                        .position(x: width / 2, y: currentY)
                        .transition(.opacity)
                }
                if lower <= upper {
                    ForEach(lower...upper, id: \.self) { i in
                        let distance = i - index
                        let metrics = LineMetricsCache.shared.metrics(for: lines[i], baseFontSize: fontSize, maxWidth: textWidth)
                        KaraokeLine(text: lines[i].text, metrics: metrics, progressX: progress(for: i, distance: distance, metrics: metrics))
                            .frame(width: width)
                            .scaleEffect(distance == 0 ? 1 : OverlayLayout.secondaryScale)
                            .opacity(Self.opacity(forDistance: distance))
                            .position(x: width / 2, y: currentY + CGFloat(distance) * gap)
                            .transition(.identity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.4), value: index)
        }
        .clipped()
    }

    private func progress(for i: Int, distance: Int, metrics: LineMetrics) -> CGFloat? {
        if distance == 0 { return metrics.progressX(at: position, line: lines[i]) }
        if distance < 0 { return metrics.width }   // finished line stays coloured while it slides out
        return nil
    }

    private static func opacity(forDistance distance: Int) -> Double {
        switch distance {
        case 0: return 1
        case 1: return 0.7
        default: return 0
        }
    }
}

/// One line: white text with a coloured copy on top, masked to the sung part.
private struct KaraokeLine: View {
    let text: String
    let metrics: LineMetrics
    /// Points from the leading edge that are sung; nil for plain white.
    let progressX: CGFloat?

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .font(.system(size: metrics.fontSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .shadow(color: .black.opacity(0.9), radius: 2, x: 0, y: 1)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
            if let progressX, progressX > 0.5 {
                Text(text)
                    .font(.system(size: metrics.fontSize, weight: .bold))
                    .foregroundStyle(OverlayStyle.highlight)
                    .lineLimit(1)
                    .fixedSize()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: progressX)
                    }
            }
        }
    }
}

/// Shown while there are no lyrics: track name on the main slot, status below.
private struct StatusLines: View {
    let title: String
    let subtitle: String
    let fontSize: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let currentY = OverlayLayout.currentLineCenter(fontSize: fontSize)
            let gap = OverlayLayout.slotGap(fontSize: fontSize)
            ZStack {
                LyricText(text: title, fontSize: fontSize)
                    .frame(width: width)
                    .position(x: width / 2, y: currentY)
                LyricText(text: subtitle, fontSize: fontSize)
                    .frame(width: width)
                    .scaleEffect(OverlayLayout.secondaryScale)
                    .opacity(0.7)
                    .position(x: width / 2, y: currentY + gap)
            }
        }
        .clipped()
    }
}

/// One line of plain text in the system font, with a shadow so it stays
/// readable on any background.
private struct LyricText: View {
    let text: String
    let fontSize: Double

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, OverlayLayout.horizontalPadding)
            .shadow(color: .black.opacity(0.9), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
    }
}
