import Foundation

/// `LyricBar --probe "<title>" "<artist>" [durationSeconds]`
/// Runs the lyrics pipeline without any UI and prints what it finds.
enum Probe {
    static func run(_ args: [String]) -> Never {
        guard args.count >= 2 else {
            print("usage: LyricBar --probe <title> <artist> [durationSeconds]")
            exit(2)
        }
        let duration = args.count >= 3 ? (Double(args[2]) ?? 0) : 0
        let track = TrackInfo(id: "", title: args[0], artist: args[1], album: "", duration: duration)
        let resolver = LyricsResolver(providers: [
            AppleMusicCacheProvider(store: nil, maxWait: 0),
            LRCLIBProvider(store: nil, isEnabled: { true }),
        ])

        let done = DispatchSemaphore(value: 0)
        Task {
            if let doc = await resolver.resolve(track) {
                print("source: \(doc.source)  timing: \(doc.timing.rawValue)  lines: \(doc.lines.count)  lang: \(doc.language ?? "-")")
                for line in doc.lines.prefix(6) {
                    let words = line.words.isEmpty ? "" : "  (\(line.words.count) words)"
                    let tr = line.translation.map { "  ⇢ \($0.prefix(20))…" } ?? ""
                    print(String(format: "  %7.3f – %7.3f  %@%@%@", line.start, line.end, String(line.text.prefix(24)), words, tr))
                }
            } else {
                print("no lyrics found")
            }
            done.signal()
        }
        done.wait()
        exit(0)
    }
}
