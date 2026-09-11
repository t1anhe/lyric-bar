import CryptoKit
import Foundation

/// Our own on-disk copy of lyrics we have already resolved, keyed by the track's
/// content key. Lives in ~/Library/Application Support/LyricBar/lyrics.
final class LyricsStore {
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        directory = base.appendingPathComponent("LyricBar/lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    enum Format: String {
        case ttml, lrc
    }

    func load(for track: TrackInfo) -> (format: Format, text: String)? {
        for format in [Format.ttml, .lrc] {
            let url = fileURL(for: track, format: format)
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                return (format, text)
            }
        }
        return nil
    }

    func save(_ text: String, format: Format, for track: TrackInfo) {
        let url = fileURL(for: track, format: format)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.warn("Could not save lyrics to \(url.path): \(error)")
        }
    }

    private func fileURL(for track: TrackInfo, format: Format) -> URL {
        let digest = SHA256.hash(data: Data(track.contentKey.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined().prefix(24)
        return directory.appendingPathComponent("\(name).\(format.rawValue)")
    }
}
