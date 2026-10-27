import Foundation

/// Share of a subscription's usage attributed to one app, or to one project inside it.
struct UsageShare: Identifiable, Equatable {
    let name: String
    /// 0...1 of the usage seen on this Mac.
    let share: Double
    var children: [UsageShare] = []

    var id: String { name }
}

/// Estimates which apps and projects consume a subscription, from the logs the CLIs keep on
/// this Mac. Servers do not expose a per-app split, so shares are token-weighted estimates;
/// claude.ai, cloud tasks and other machines are invisible here.
actor UsageBreakdown {
    struct Record: Equatable {
        let date: Date
        var app: String
        /// Canonical project path (see `projectKey`); labels are derived when aggregating.
        let project: String
        let weight: Double
        /// Claude API response id: the same response can appear in several transcripts (forks, resumes).
        var responseID: String? = nil
        /// Codex thread id, and the thread that spawned it for subagents.
        var thread: String? = nil
        var parentThread: String? = nil
    }

    static let delegateApp = "Skill delegate"

    static let shared = UsageBreakdown()

    private let home = FileManager.default.homeDirectoryForCurrentUser
    /// Parsed records per provider and log file, reused while the file is unchanged.
    private var cache: [SubscriptionUsage.Kind: [String: (stamp: String, records: [Record])]] = [:]

    /// `extra` holds records gathered elsewhere (remote hosts); they join the local ones.
    func shares(for kind: SubscriptionUsage.Kind, since start: Date, extra: [Record] = []) -> [UsageShare] {
        let files: [URL]
        let parse: (Data) -> [Record]
        switch kind {
        case .claude:
            files = Self.jsonlFiles(under: home.appendingPathComponent(".claude/projects"), modifiedSince: start)
            parse = Self.parseClaude
        case .codex:
            let root = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".codex")
            files = Self.jsonlFiles(under: root.appendingPathComponent("sessions"), modifiedSince: start)
            parse = Self.parseCodex
        }

        var records: [Record] = []
        var fresh: [String: (stamp: String, records: [Record])] = [:]
        let previous = cache[kind] ?? [:]
        for file in files {
            let path = file.path
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let stamp = "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)-\(values?.fileSize ?? 0)"
            if let cached = previous[path], cached.stamp == stamp {
                fresh[path] = cached
                records += cached.records
                continue
            }
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            let parsed = parse(data)
            fresh[path] = (stamp, parsed)
            records += parsed
        }
        cache[kind] = fresh
        records += extra
        if kind == .claude {
            records = Self.deduplicatedResponses(records)
        }
        if kind == .codex {
            // Classified at aggregation time: a delegate run's meta.json is only written when it ends.
            let delegated = Self.delegateThreads(in: home.appendingPathComponent(".cache/codex-delegate"))
            var parents: [String: String] = [:]
            for record in records { if let t = record.thread, let p = record.parentThread { parents[t] = p } }
            // Subagents (and their own subagents) count for the delegate run that spawned them.
            func isDelegated(_ thread: String?) -> Bool {
                var current = thread
                for _ in 0..<8 {
                    guard let id = current else { return false }
                    if delegated.contains(id) { return true }
                    current = parents[id]
                }
                return false
            }
            for index in records.indices where isDelegated(records[index].thread) {
                records[index].app = Self.delegateApp
            }
        }
        return Self.aggregate(records.filter { $0.date >= start })
    }

    // MARK: - Aggregation

    /// One record per Claude response across all transcripts, keeping its most complete usage.
    static func deduplicatedResponses(_ records: [Record]) -> [Record] {
        var best: [String: Record] = [:]
        var unique: [Record] = []
        for record in records {
            guard let id = record.responseID else { unique.append(record); continue }
            if let kept = best[id], kept.weight >= record.weight { continue }
            best[id] = record
        }
        return unique + best.values
    }

    /// Display names: the folder name, or "parent/folder" when two projects share a folder name.
    static func projectLabels(_ keys: some Sequence<String>) -> [String: String] {
        let keys = Set(keys)
        let byName = Dictionary(grouping: keys) { URL(fileURLWithPath: $0).lastPathComponent }
        var labels: [String: String] = [:]
        for (name, group) in byName {
            for key in group {
                let parent = URL(fileURLWithPath: key).deletingLastPathComponent().lastPathComponent
                labels[key] = group.count > 1 && !parent.isEmpty ? "\(parent)/\(name)" : name
            }
        }
        return labels
    }

    /// Projects past `maxProjects`, or negligible both overall (`minShare`) and within their app
    /// (under 10 %), fold into "Other projects". A small app still shows where its usage went.
    static func aggregate(_ records: [Record], maxProjects: Int = 5, minShare: Double = 0.005) -> [UsageShare] {
        let total = records.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        let byApp = Dictionary(grouping: records, by: \.app)
        return byApp.map { app, appRecords in
            let groups = Dictionary(grouping: appRecords, by: \.project)
            let labels = projectLabels(groups.keys)
            let byProject = groups
                .map { UsageShare(name: labels[$0.key] ?? $0.key, share: $0.value.reduce(0) { $0 + $1.weight } / total) }
                .sorted { $0.share > $1.share }
            let appShare = byProject.reduce(0) { $0 + $1.share }
            var projects = Array(byProject.prefix(maxProjects).filter { $0.share >= min(minShare, appShare / 10) })
            let rest = appShare - projects.reduce(0) { $0 + $1.share }
            if rest >= minShare / 10 { projects.append(UsageShare(name: "Other projects", share: rest)) }
            return UsageShare(name: app, share: appShare, children: projects)
        }
        .sorted { $0.share > $1.share }
    }

    // MARK: - Claude Code transcripts (~/.claude/projects/**/*.jsonl)

    /// Assistant lines only (substring pre-filter); within a file, a response written as several
    /// lines (one per content block) keeps its largest usage, the final one.
    static func parseClaude(_ data: Data) -> [Record] {
        var records: [Record] = []
        var indexByID: [String: Int] = [:]
        forEachLine(of: data, containing: [#""type":"assistant""#]) { line in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let date = (object["timestamp"] as? String).flatMap(UsageFetcher.parseISODate)
            else { return }
            func tokens(_ name: String) -> Double { (usage[name] as? NSNumber)?.doubleValue ?? 0 }
            let weight = tokens("input_tokens") + 5 * tokens("output_tokens")
                + 1.25 * tokens("cache_creation_input_tokens") + 0.1 * tokens("cache_read_input_tokens")
            guard weight > 0 else { return }
            let id = (message["id"] as? String) ?? (object["requestId"] as? String)
            let record = Record(
                date: date,
                app: claudeApp(object["entrypoint"] as? String),
                project: projectKey(object["cwd"] as? String),
                weight: weight,
                responseID: id
            )
            if let id, let index = indexByID[id] {
                if weight > records[index].weight { records[index] = record }
            } else {
                if let id { indexByID[id] = records.count }
                records.append(record)
            }
        }
        return records
    }

    static func claudeApp(_ entrypoint: String?) -> String {
        switch entrypoint {
        case "claude-desktop": "Claude Desktop"
        case "cli": "Claude Code CLI"
        case "sdk-cli": "claude -p (scripts)"
        case "sdk-py": "Python SDK"
        case "sdk-ts": "TypeScript SDK"
        case "claude-vscode": "VS Code"
        case let value?: value
        case nil: "Unknown"
        }
    }

    // MARK: - Codex sessions (~/.codex/sessions/**/rollout-*.jsonl)

    static func parseCodex(_ data: Data) -> [Record] {
        var app = "Codex"
        var project = "Unknown"
        var thread: String?
        var parentThread: String?
        var records: [Record] = []
        var previous: Double = 0
        forEachLine(of: data, containing: [#""session_meta""#, #""token_count""#]) { line in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { return }
            if object["type"] as? String == "session_meta" {
                app = codexApp(payload["originator"] as? String, subagent: payload["source"] is [String: Any])
                thread = payload["id"] as? String
                let spawn = ((payload["source"] as? [String: Any])?["subagent"] as? [String: Any])?["thread_spawn"] as? [String: Any]
                parentThread = spawn?["parent_thread_id"] as? String
                project = projectKey(payload["cwd"] as? String)
                return
            }
            guard payload["type"] as? String == "token_count",
                  let total = (payload["info"] as? [String: Any])?["total_token_usage"] as? [String: Any],
                  let date = (object["timestamp"] as? String).flatMap(UsageFetcher.parseISODate)
            else { return }
            func tokens(_ name: String) -> Double { (total[name] as? NSNumber)?.doubleValue ?? 0 }
            let cached = tokens("cached_input_tokens")
            // Totals are cumulative per session; diffs keep the part spent inside the window.
            let cumulative = (tokens("input_tokens") - cached) + 0.1 * cached + 5 * tokens("output_tokens")
            if cumulative > previous {
                records.append(Record(date: date, app: app, project: project, weight: cumulative - previous,
                                      thread: thread, parentThread: parentThread))
                previous = cumulative
            }
        }
        return records
    }

    static func codexApp(_ originator: String?, subagent: Bool) -> String {
        let name = switch originator {
        case "codex_exec": "codex exec (scripts)"
        case "codex_cli_rs": "Codex CLI"
        case "codex_vscode": "Codex VS Code"
        case let value?: value
        case nil: "Codex"
        }
        return subagent ? "\(name), subagents" : name
    }

    /// Thread ids started by the delegate skill (`~/.cache/codex-delegate/<run>/meta.json`).
    static func delegateThreads(in runs: URL) -> Set<String> {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: runs, includingPropertiesForKeys: nil)) ?? []
        return Set(dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return meta["thread_id"] as? String
        })
    }

    // MARK: - Helpers

    /// Canonical project path: worktrees are credited to their repository.
    /// `<repo>/.claude/worktrees/<name>` → `<repo>`; `~/.codex/worktrees/<id>/<repo>` → `<repo>`.
    static func projectKey(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Unknown" }
        let parts = URL(fileURLWithPath: cwd).standardizedFileURL.pathComponents
        if let index = parts.lastIndex(of: "worktrees"), index >= 1 {
            switch parts[index - 1] {
            case ".claude" where index >= 2:
                return NSString.path(withComponents: Array(parts[..<(index - 1)]))
            case ".codex" where parts.count > index + 2:
                return parts[index + 2]
            default: break
            }
        }
        let path = NSString.path(withComponents: parts)
        return path == FileManager.default.homeDirectoryForCurrentUser.path ? "~" : path
    }

    private static func jsonlFiles(under root: URL, modifiedSince start: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { url in
            url.pathExtension == "jsonl"
                && ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) >= start
        }
    }

    /// Calls `body` with each newline-separated line containing one of `needles` (cheap pre-filter
    /// before JSON parsing). Lines are views into `data`, valid only inside `body`: copying them
    /// and Data.split/range(of:) dominated the scan of gigabytes of logs.
    private static func forEachLine(of data: Data, containing needles: [String], _ body: (Data) -> Void) {
        let patterns = needles.map { Array($0.utf8) }
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var start = 0
            let count = buffer.count
            while start < count {
                let end = memchr(base + start, Int32(UInt8(ascii: "\n")), count - start)
                    .map { UnsafeRawPointer($0) - base } ?? count
                let length = end - start
                if length > 0 {
                    let keep = patterns.contains { p in
                        p.withUnsafeBytes { memmem(base + start, length, $0.baseAddress, p.count) != nil }
                    }
                    if keep {
                        body(Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base + start), count: length, deallocator: .none))
                    }
                }
                start = end + 1
            }
        }
    }
}
