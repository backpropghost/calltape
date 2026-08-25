import Foundation
import OSLog

/// App-wide logging. Goes to the unified log (visible in Console.app) and to a
/// rotating text file under ~/Library/Logs/CallTape for easy export and, later,
/// crash/error reporting.
enum Log {
    private static let logger = Logger(subsystem: "com.calltape.app", category: "app")
    private static let queue = DispatchQueue(label: "com.calltape.log")
    private static let maxBytes = 2_000_000

    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CallTape", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("calltape.log")
    }()

    static func info(_ message: String)  { logger.info("\(message, privacy: .public)");  write("INFO", message) }
    static func error(_ message: String) { logger.error("\(message, privacy: .public)"); write("ERROR", message) }
    static func debug(_ message: String) { logger.debug("\(message, privacy: .public)"); write("DEBUG", message) }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static func write(_ level: String, _ message: String) {
        let line = "\(stamp.string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            rotateIfNeeded()
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private static func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              size > maxBytes else { return }
        let archived = fileURL.deletingPathExtension().appendingPathExtension("1.log")
        try? FileManager.default.removeItem(at: archived)
        try? FileManager.default.moveItem(at: fileURL, to: archived)
    }
}
