# lyric-bar

Floating desktop lyrics for Apple Music on macOS, in the spirit of NetEase Cloud
Music's desktop lyrics. A small menu bar app that watches what Music.app is
playing and shows the current and next line in a transparent, always-on-top
window.

- **First-party lyrics.** Music.app already downloads word-synced lyrics for every
  track it plays; LyricBar reads them from Music's own cache on disk. No accounts,
  no tokens, no third-party lyrics services required.
- **Word-level timing** (TTML "syllable lyrics"), translations where Apple provides them.
- Optional fallback to the open [LRCLIB](https://lrclib.net) database (can be turned off).
- Native Swift + AppKit + SwiftUI. Builds with the Command Line Tools alone, no Xcode.

## Requirements

- macOS 14 or newer (developed on macOS 26)
- Apple Music (Music.app) with an Apple Music subscription
- Xcode Command Line Tools: `xcode-select --install`

## Build and run

```bash
make run          # swift build, wrap into build/LyricBar.app, launch it
make stop         # quit the app
make logs         # follow ~/Library/Logs/LyricBar/lyricbar.log
```

On first launch macOS asks whether LyricBar may control Music. Allow it: that is
how the app reads the current track and playback position.

A music note icon appears in the menu bar. Click it to toggle the overlay,
adjust the timing offset and the font size, or quit.

The overlay never gets in the way: clicks pass straight through it, and it fades
out while the mouse pointer is over it so you can read and click whatever is
underneath. To reposition it, **right-click and drag** the lyrics, or hold **⌥**
and drag. It snaps to the screen edges (the bottom edge is the top of the Dock)
and to the horizontal and vertical centre lines. The position is remembered.

Right-drag works through a session-wide event tap, which macOS only allows with
the Accessibility permission (System Settings > Privacy & Security >
Accessibility). LyricBar asks once on first launch; ⌥-drag needs no permission.

The current line fills with colour word by word as it is sung (Apple's lyrics
carry word timing; for line-timed lyrics the fill is interpolated).

## How it works

```
Music.app ──notifications + AppleScript──▶ AppleMusicMonitor ──▶ PlaybackClock ─┐
                                                                                ▼
~/Library/Caches/com.apple.Music/fsCachedData ──▶ AppleMusicCacheProvider ──▶ OverlayView
                                                    (TTML parser)             (menu bar popover)
                                     lrclib.net ──▶ LRCLIBProvider (fallback)
```

1. `AppleMusicMonitor` listens for `com.apple.Music.playerInfo` distributed
   notifications (play / pause / track change) and polls Music once a second via
   AppleScript for the playback position.
2. `PlaybackClock` extrapolates between polls so the UI can run at any frame rate.
3. When the track changes, `LyricsResolver` asks each `LyricsProvider` in order.
   `AppleMusicCacheProvider` scans Music's URL cache for the JSON response of the
   `songs/{id}?include=syllable-lyrics` request Music makes for every track and
   parses the embedded TTML. A cached song is accepted when its title and
   duration match, or when its duration matches and the file was written after
   the current track started (Music reports library titles such as "就是现在"
   while the catalog response uses the UI language, "Now Is the Time"), or when
   it is the only cached song with that duration. Results are copied to
   `~/Library/Application Support/LyricBar/lyrics`.
4. `OverlayView` (SwiftUI) renders the current line and the next one inside a
   borderless, non-activating `NSPanel` that joins all Spaces and floats above
   full-screen apps.

## Development notes

- `make probe TITLE="Song" ARTIST="Artist" DURATION=208` runs the lyrics pipeline
  without the UI and prints what it finds.
- The app is ad-hoc signed. The Automation permission survived rebuilds in
  testing, but the Accessibility grant is tied to the code signature and may
  stop working after a rebuild (the switch stays on but the event tap cannot be
  created; remove and re-add LyricBar in System Settings). A self-signed
  "Code Signing" certificate from Keychain Access gives a stable identity:
  `CODESIGN_IDENTITY="Your Cert Name" make app`.
- `make install` copies the bundle to `/Applications` so Spotlight and
  launch-at-login can find it.
- Logs: `~/Library/Logs/LyricBar/lyricbar.log` and `log stream --predicate 'subsystem == "dev.lyricbar"'`.

## Roadmap

- [x] v0.1 Apple Music, first-party lyrics, current + next line, menu bar controls
- [x] v0.2 Word-by-word highlight, click-through with hover fade, right-drag with edge snapping
- [ ] v0.2.x Translation line, launch at login, hide when idle
- [ ] v0.3 Spotify, multiple displays, style presets
- [ ] v0.4 Manual lyrics search when the match is wrong, local `.lrc` files
