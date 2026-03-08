import Foundation
import OSLog

/// Persists errors to ~/Library/Logs/LLMStatus/errors.log
/// Also forwards to OSLog for Console.app visibility.
final class FileLogger: Sendable {
    static let shared = FileLogger()

    private let logURL: URL
    private let osLog = Logger(subsystem: "com.llmstatus", category: "FileLogger")

    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LLMStatus")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logURL = logsDir.appendingPathComponent("errors.log")
    }

    /// Log an error with source context
    func error(_ message: String, source: String) {
        let entry = format(level: "ERROR", source: source, message: message)
        osLog.error("\(entry)")
        append(entry)
    }

    /// Log a warning with source context
    func warning(_ message: String, source: String) {
        let entry = format(level: "WARN", source: source, message: message)
        osLog.warning("\(entry)")
        append(entry)
    }

    /// Path to the log file (for display in settings)
    var logFilePath: String { logURL.path }

    private func format(level: String, source: String, message: String) -> String {
        let date = ISO8601DateFormatter().string(from: Date())
        return "[\(date)] [\(level)] [\(source)] \(message)"
    }

    private func append(_ entry: String) {
        let line = entry + "\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path) {
            // Rotate if > 1MB
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
               let size = attrs[.size] as? UInt64, size > 1_000_000 {
                let backupURL = logURL.deletingLastPathComponent()
                    .appendingPathComponent("errors.log.old")
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.moveItem(at: logURL, to: backupURL)
            }

            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logURL)
        }
    }
}
