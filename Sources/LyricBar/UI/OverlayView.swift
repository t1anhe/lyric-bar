import SwiftUI

/// The floating lyrics. Fully transparent background; lines scroll upward: the
/// finished line slides up and fades out, the next line moves up into the main
/// slot, and the line after it slides in from below.
struct OverlayView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { context in
            let position = state.clock.position(at: context.date) + state.offset
            content(at: position)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // macOS lets clicks fall through fully transparent window pixels, so the
        // window could not be dragged. Keep an invisible fill while unlocked.
        .background(Color.black.opacity(state.locked ? 0 : 0.01))
    }

    @ViewBuilder
    private func content(at position: TimeInterval) -> some View {
        if let doc = state.lyrics {
            LyricsScroller(lines: doc.lines, index: doc.index(at: position) ?? -1, fontSize: state.fontSize)
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
}

private struct LyricsScroller: View {
    let lines: [LyricLine]
    /// Current line, or -1 before the first line.
    let index: Int
    let fontSize: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
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
                        LyricText(text: lines[i].text, fontSize: fontSize)
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

    private static func opacity(forDistance distance: Int) -> Double {
        switch distance {
        case 0: return 1
        case 1: return 0.7
        default: return 0
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

/// One line of text in the system font, with a shadow so it stays readable on
/// any background.
private struct LyricText: View {
    let text: String
    let fontSize: Double

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .shadow(color: .black.opacity(0.9), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
    }
}
