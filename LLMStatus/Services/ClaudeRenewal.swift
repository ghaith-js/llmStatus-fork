import Foundation

/// Renews this Mac's Claude Code token by sending one tiny request through the `claude` CLI.
/// The CLI refreshes its own login (with its own locking), so LLM Status never touches the
/// refresh token. Needed when sessions run in the Claude desktop app, whose login is separate
/// and never renews the CLI's keychain item.
enum ClaudeRenewal {
    /// Where installers put `claude`; a GUI app does not inherit the shell's PATH.
    static func candidates(home: String = NSHomeDirectory()) -> [String] {
        ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
         "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude"]
    }

    /// Arguments of the renewing call: the smallest model, no session file left in the logs.
    static let arguments = ["-p", "--model", "haiku", "--no-session-persistence", "Reply with OK."]

    static func locateCLI() -> URL? {
        if let path = candidates().first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        // Fall back to the login shell's PATH (nvm, asdf and other version managers).
        guard let output = run(URL(fileURLWithPath: "/bin/zsh"), ["-lc", "command -v claude"], timeout: 10),
              output.status == 0 else { return nil }
        let path = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// Nil on success, else a short reason for the row.
    static func renew() async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let cli = locateCLI() else { return "Claude Code CLI not found" }
            guard let output = run(cli, arguments, timeout: 90) else { return "Claude Code did not answer" }
            guard output.status == 0 else {
                FileLogger.shared.error("Renew failed with status \(output.status)", source: "Claude")
                return "Claude Code could not renew its login: run claude in a terminal"
            }
            return nil
        }.value
    }

    /// Runs a process from the temporary folder with stdin closed; nil when it could not start or timed out.
    private static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, data: Data)? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        let directory = executable.deletingLastPathComponent().path
        environment["PATH"] = ([directory] + (environment["PATH"].map { [$0] } ?? ["/usr/bin:/bin"])).joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        var timedOut = false
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { timedOut = true; process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return timedOut ? nil : (process.terminationStatus, data)
    }
}
