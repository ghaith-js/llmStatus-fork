import Foundation
import OSLog

private let logger = Logger(subsystem: "com.llmstatus", category: "XAIFetcher")

/// Fetches xAI status by running a Python script that uses StealthyFetcher
/// to bypass Cloudflare. Results are cached for 10 minutes.
enum XAIFetcher {
    private static let cacheDuration: TimeInterval = 600 // 10 minutes
    private static var cachedStatus: ServiceStatus?
    private static var cachedIncidents: [Incident] = []
    private static var lastFetchDate: Date?
    private static var isFetching = false
    /// Current fetch step for UI progress display
    static var progressMessage: String?

    /// Whether we have a cached result that hasn't expired
    static var hasCachedResult: Bool {
        guard let lastFetch = lastFetchDate else { return false }
        return Date().timeIntervalSince(lastFetch) < cacheDuration
    }

    private struct ScriptResult: Codable {
        let status: String
        let incidents: [ScriptIncident]
        let error: String?

        struct ScriptIncident: Codable {
            let id: String
            let name: String
        }
    }

    static func fetchStatus(baseURL: URL) async -> ServiceStatus {
        await refreshCacheIfNeeded()
        return cachedStatus ?? .unknown
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        await refreshCacheIfNeeded()
        return cachedIncidents
    }

    private static func refreshCacheIfNeeded() async {
        // Return cached result if still fresh
        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < cacheDuration {
            return
        }

        // Prevent concurrent fetches
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        logger.info("Fetching xAI status via Python script...")
        progressMessage = "Launching browser..."

        guard let result = await runPythonScript() else {
            logger.warning("Python script returned no result")
            cachedStatus = .unknown
            cachedIncidents = []
            lastFetchDate = Date()
            progressMessage = nil
            return
        }

        progressMessage = "Parsing response..."
        cachedStatus = mapStatus(result.status)
        cachedIncidents = result.incidents.map { inc in
            Incident(
                id: inc.id,
                name: inc.name,
                impact: .major,
                status: .investigating,
                createdAt: Date(),
                resolvedAt: nil,
                shortlink: "https://status.x.ai",
                updates: [],
                affectedComponents: []
            )
        }
        lastFetchDate = Date()

        if let error = result.error {
            logger.warning("xAI fetch error: \(error)")
        }

        progressMessage = nil
        logger.info("xAI status: \(result.status)")
    }

    private static func runPythonScript() async -> ScriptResult? {
        // Find the script relative to the executable or in known locations
        let scriptName = "fetch_xai_status.py"
        let scriptPath = findScript(named: scriptName)

        guard let path = scriptPath else {
            logger.error("Cannot find \(scriptName)")
            return nil
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()

                // Use the venv python if available, otherwise system python3
                let venvPython = "/tmp/scrapling-test/bin/python3"
                if FileManager.default.fileExists(atPath: venvPython) {
                    process.executableURL = URL(fileURLWithPath: venvPython)
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["python3"]
                }

                if process.executableURL?.lastPathComponent == "env" {
                    process.arguments = ["python3", path]
                } else {
                    process.arguments = [path]
                }

                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let result = try JSONDecoder().decode(ScriptResult.self, from: data)
                    continuation.resume(returning: result)
                } catch {
                    logger.error("Failed to run Python script: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func findScript(named name: String) -> String? {
        // Check relative to the executable
        let execURL = Bundle.main.executableURL?.deletingLastPathComponent()
        var candidates: [String] = []
        if let execURL {
            candidates.append(execURL.appendingPathComponent("../../../scripts/\(name)").path)
            candidates.append(execURL.appendingPathComponent("../../scripts/\(name)").path)
            candidates.append(execURL.appendingPathComponent("scripts/\(name)").path)
        }
        candidates.append(FileManager.default.currentDirectoryPath + "/scripts/\(name)")
        candidates.append(Bundle.main.bundlePath + "/Contents/Resources/scripts/\(name)")

        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                return resolved
            }
        }
        return nil
    }

    private static func mapStatus(_ status: String) -> ServiceStatus {
        switch status {
        case "operational": .operational
        case "degraded": .degraded
        case "majorOutage": .majorOutage
        case "critical": .critical
        default: .unknown
        }
    }
}
