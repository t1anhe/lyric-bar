import SwiftUI

/// Contents of the menu bar popover.
struct PopoverView: View {
    @EnvironmentObject var state: AppState
    let reloadLyrics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "music.note.list")
                Text("LyricBar").font(.headline)
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .foregroundStyle(.secondary).font(.caption)
            }

            GroupBox("Now Playing") {
                VStack(alignment: .leading, spacing: 4) {
                    if let track = state.track {
                        Text(track.title).fontWeight(.semibold).lineLimit(1)
                        Text("\(track.artist) — \(track.album)").foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("Nothing playing").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(state.snapshot?.state.rawValue.capitalized ?? "—")
                        Spacer()
                        Text(state.lyricsStatus).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle("Show lyrics overlay", isOn: $state.overlayVisible)
            VStack(alignment: .leading, spacing: 4) {
                Text("Move: right-click and drag the lyrics, or hold ⌥ and drag. They snap to the screen edges and centre. Clicks pass through otherwise.")
                    .font(.caption).foregroundStyle(.secondary)
                if !state.accessibilityTrusted {
                    HStack {
                        Text("Right-drag needs Accessibility access.").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings") { OverlayWindowController.openAccessibilitySettings() }
                            .font(.caption).controlSize(.small)
                    }
                }
            }

            HStack {
                Text("Offset")
                Spacer()
                Stepper(value: $state.offset, in: -10...10, step: 0.1) {
                    Text(String(format: "%+.1f s", state.offset)).monospacedDigit()
                }
                Button("Reset") { state.offset = 0 }.disabled(state.offset == 0)
            }

            HStack {
                Text("Font size")
                Slider(value: $state.fontSize, in: 18...64)
                Text("\(Int(state.fontSize))").monospacedDigit().frame(width: 28)
            }

            Toggle("Use LRCLIB when Apple Music has no lyrics", isOn: $state.lrclibEnabled)

            Divider()

            HStack {
                Button("Reload lyrics", action: reloadLyrics).disabled(state.track == nil)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
