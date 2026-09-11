import Foundation
import os

/// Tiny logger: writes to ~/Library/Logs/LyricBar/lyricbar.log, to the unified log
/// (subsystem "dev.lyricbar") and to stdout when launched from a terminal.
enum Log {
    private static let logger = Logger(subsystem: "dev.lyricbar", category: "app")
    private static let queue = DispatchQueue(label: "dev.lyricbar.log")

    private static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LyricBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("lyricbar.log")
        // Keep the file from growing forever.
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
           size > 5_000_000 {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) {
        write("INFO", message)
        logger.info("\(message, privacy: .public)")
    }

    static func warn(_ message: String) {
        write("WARN", message)
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        write("ERROR", message)
        logger.error("\(message, privacy: .public)")
    }

    private static func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        print(line, terminator: "")
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
