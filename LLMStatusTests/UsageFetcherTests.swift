import Foundation
import Testing
@testable import LLMStatus

@Suite("Subscription usage")
struct UsageFetcherTests {
    @Test("Claude weekly and 5 h limits are read, microsecond dates included")
    func claude() {
        let body = #"{"five_hour":{"utilization":1.0,"resets_at":"2026-10-27T20:00:00.196176+00:00"},"seven_day":{"utilization":33.0,"resets_at":"2026-10-31T23:00:00.196198+00:00"},"seven_day_opus":null}"#
        let usage = UsageFetcher.parseClaude(Data(body.utf8))
        #expect(usage.error == nil)
        #expect(usage.weekly?.percent == 33)
        #expect(usage.session?.percent == 1)
        let expected = ISO8601DateFormatter().date(from: "2026-10-31T23:00:00Z")!
        #expect(abs(usage.weekly!.resetsAt!.timeIntervalSince(expected) - 0.196) < 0.001)
    }

    @Test("Claude response without a weekly limit is an error, not 0 %")
    func claudeMissing() {
        let usage = UsageFetcher.parseClaude(Data(#"{"five_hour":null,"seven_day":null}"#.utf8))
        #expect(usage.weekly == nil)
        #expect(usage.error != nil)
    }

    @Test("Codex weekly window is found whether sent as primary or secondary")
    func codexWindows() {
        let weeklyOnly = #"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":604800,"reset_after_seconds":496591,"reset_at":1793610049},"secondary_window":null}}"#
        let a = UsageFetcher.parseCodex(Data(weeklyOnly.utf8))
        #expect(a.weekly?.percent == 4)
        #expect(a.session == nil)
        #expect(a.plan == "Pro")
        #expect(a.weekly?.resetsAt == Date(timeIntervalSince1970: 1793610049))

        let both = #"{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_at":1},"secondary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_at":2}}}"#
        let b = UsageFetcher.parseCodex(Data(both.utf8))
        #expect(b.weekly?.percent == 40)
        #expect(b.weekly?.label == "weekly")
        #expect(b.session?.percent == 12)
        #expect(b.session?.label == "5h")
    }

    @Test("Codex without a weekly window reports it instead of inventing one")
    func codexNoWeekly() {
        let body = #"{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000},"secondary_window":null}}"#
        let usage = UsageFetcher.parseCodex(Data(body.utf8))
        #expect(usage.weekly == nil)
        #expect(usage.error == "No weekly limit reported")
        #expect(UsageFetcher.parseCodex(Data("<html>".utf8)).error == "Unreadable usage data")
    }

    @Test("Window labels follow the server-provided duration", arguments: [
        (3600, "1h"), (18000, "5h"), (604800, "weekly"), (2592000, "30d")
    ])
    func windowLabel(value: (Int, String)) {
        #expect(SubscriptionUsage.Window(percent: 0, resetsAt: nil, seconds: value.0).label == value.1)
    }
}

@Suite("Usage breakdown by app and project")
struct UsageBreakdownTests {
    @Test("Claude lines are deduplicated per response and weighted by token class")
    func claude() {
        let line = #"{"type":"assistant","timestamp":"2026-10-27T10:00:00.000Z","entrypoint":"sdk-cli","cwd":"/Users/x/project-a","message":{"id":"msg_1","usage":{"input_tokens":100,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000}}}"#
        let user = #"{"type":"user","message":{"content":"hi"}}"#
        let records = UsageBreakdown.parseClaude(Data([line, line, user].joined(separator: "\n").utf8))
        #expect(records.count == 1)
        #expect(records.first?.app == "claude -p (scripts)")
        #expect(records.first?.project == "/Users/x/project-a")
        #expect(abs(records.first!.weight - (100 + 5 * 10 + 0.1 * 1000)) < 1e-9)
    }

    @Test("Codex cumulative totals become per-event deltas tagged with the session's app")
    func codex() {
        let lines = [
            #"{"type":"session_meta","payload":{"originator":"codex_exec","source":{"subagent":{}},"cwd":"/Users/x/llmStatus/.claude/worktrees/feat"}}"#,
            #"{"timestamp":"2026-10-27T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":0}}}}"#,
            #"{"timestamp":"2026-10-27T10:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":0}}}}"#,
            #"{"timestamp":"2026-10-27T10:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3000,"cached_input_tokens":1000,"output_tokens":100}}}}"#,
        ]
        let records = UsageBreakdown.parseCodex(Data(lines.joined(separator: "\n").utf8))
        // (3000 - 1000 cached) + 0.1 * 1000 + 5 * 100 = 2600 cumulative, minus the previous 1000
        #expect(records.map(\.weight) == [1000, 1600])
        #expect(records.first?.app == "codex exec (scripts), subagents")
        #expect(records.first?.project == "/Users/x/llmStatus")
    }

    @Test("Claude keeps the final usage of a response and reads the envelope cwd, not tool input")
    func claudeFinalUsage() {
        func line(_ output: Int) -> String {
            #"{"type":"assistant","timestamp":"2026-10-27T10:00:00Z","message":{"id":"msg_9","content":[{"type":"tool_use","input":{"cwd":"/tmp/wrong"}}],"usage":{"input_tokens":0,"output_tokens":\#(output)}},"cwd":"/Users/x/right","entrypoint":"cli"}"#
        }
        let records = UsageBreakdown.parseClaude(Data([line(1), line(40), line(3)].joined(separator: "\n").utf8))
        #expect(records.count == 1)
        #expect(records.first?.weight == 200)
        #expect(records.first?.project == "/Users/x/right")
    }

    @Test("A Claude response copied into several transcripts counts once, at its largest")
    func claudeCrossFile() {
        let now = Date()
        let a = UsageBreakdown.Record(date: now, app: "A", project: "p", weight: 5, responseID: "msg_1")
        let b = UsageBreakdown.Record(date: now, app: "A", project: "q", weight: 9, responseID: "msg_1")
        let c = UsageBreakdown.Record(date: now, app: "A", project: "p", weight: 1)
        let kept = UsageBreakdown.deduplicatedResponses([a, b, c])
        #expect(kept.count == 2)
        #expect(kept.reduce(0) { $0 + $1.weight } == 10)
    }

    @Test("Projects are identified by path; same folder names are disambiguated")
    func projectIdentity() {
        #expect(UsageBreakdown.projectKey("/Users/x/repo/.claude/worktrees/feat") == "/Users/x/repo")
        #expect(UsageBreakdown.projectKey("/Users/x/.codex/worktrees/ab12/repo") == "repo")
        #expect(UsageBreakdown.projectKey(nil) == "Unknown")
        let labels = UsageBreakdown.projectLabels(["/a/clientA/web", "/a/clientB/web", "/a/solo"])
        #expect(labels["/a/clientA/web"] == "clientA/web")
        #expect(labels["/a/clientB/web"] == "clientB/web")
        #expect(labels["/a/solo"] == "solo")
    }

    @Test("Codex sessions keep their thread and parent ids for delegate attribution")
    func codexThreads() {
        let lines = [
            #"{"type":"session_meta","payload":{"id":"child","originator":"codex_exec","source":{"subagent":{"thread_spawn":{"parent_thread_id":"run-1"}}},"cwd":"/x/project-b"}}"#,
            #"{"timestamp":"2026-10-27T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"output_tokens":0}}}}"#,
        ]
        let record = UsageBreakdown.parseCodex(Data(lines.joined(separator: "\n").utf8)).first
        #expect(record?.thread == "child")
        #expect(record?.parentThread == "run-1")
    }

    @Test("Delegate run directories yield their Codex thread ids")
    func delegateThreads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (name, body) in [("run-a", #"{"thread_id":"t1"}"#), ("run-b", #"{"thread_id":null}"#), ("run-c", "not json")] {
            let dir = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(body.utf8).write(to: dir.appendingPathComponent("meta.json"))
        }
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(UsageBreakdown.delegateThreads(in: root) == ["t1"])
        #expect(UsageBreakdown.delegateThreads(in: root.appendingPathComponent("missing")).isEmpty)
    }

    @Test("Aggregation groups apps, ranks projects and folds the tail into Other")
    func aggregate() {
        let now = Date()
        let records = (1...7).map { UsageBreakdown.Record(date: now, app: "A", project: "p\($0)", weight: Double($0)) }
            + [UsageBreakdown.Record(date: now, app: "B", project: "q", weight: 72)]
        let shares = UsageBreakdown.aggregate(records)
        #expect(shares.map(\.name) == ["B", "A"])
        #expect(abs(shares.reduce(0) { $0 + $1.share } - 1) < 1e-9)
        #expect(shares[1].children.count == 6)
        #expect(shares[1].children.last?.name == "Other projects")
        #expect(UsageBreakdown.aggregate([]).isEmpty)

        // Negligible projects fold into Other; the app keeps its full share.
        let tiny = [UsageBreakdown.Record(date: now, app: "A", project: "big", weight: 999),
                    UsageBreakdown.Record(date: now, app: "A", project: "tiny", weight: 1)]
        let folded = UsageBreakdown.aggregate(tiny)
        #expect(folded[0].share == 1)
        #expect(folded[0].children.map(\.name) == ["big", "Other projects"])
    }

    @Test("Remote collector lines become host-prefixed records; bad lines are skipped")
    func remoteParse() {
        let body = [
            #"{"d": 1793000000, "app": "Hermes", "project": "cron", "w": 12.5, "t": null, "p": null}"#,
            #"{"d": 1793000001, "app": "service-a", "project": "service-a", "w": 3, "t": "th", "p": "parent"}"#,
            #"{"d": 1793000002, "app": "Hermes", "project": "cron", "w": 0}"#,
            "not json",
        ].joined(separator: "\n")
        let records = RemoteUsage.parse(Data(body.utf8), host: "my-vps")
        #expect(records.count == 2)
        #expect(records[0].app == "my-vps · Hermes")
        #expect(records[0].project == "my-vps:/cron")
        #expect(UsageBreakdown.projectLabels([records[0].project])[records[0].project] == "cron")
        #expect(records[1].thread == "th")
        #expect(records[1].parentThread == "parent")
    }

    @Test("Hosts that look like options or carry shell characters are refused", arguments: [
        ("my-vps", true), ("user@host.example", true), ("-oProxyCommand=x", false), ("a;b", false), ("a b", false), ("", false)
    ])
    func hostValidation(value: (String, Bool)) {
        #expect(RemoteUsage.isValidHost(value.0) == value.1)
    }

    @Test("Without a local account id nothing remote is counted")
    func remoteNeedsAccount() {
        let host = RemoteUsage.Host(alias: "my-vps")
        let result = RemoteUsage.fetch(host: host, since: Date(), accountID: nil)
        #expect(result.records.isEmpty)
        #expect(result.error == "my-vps: local Codex account unknown")
        #expect(RemoteUsage.fetch(host: host, since: Date(), accountID: "$(id)").error != nil)
    }

    @Test("Collector source errors are reported instead of counting as zero")
    func remoteSourceErrors() {
        let body = #"{"error": "Hermes: OperationalError"}"# + "\n" + #"{"d": 1, "app": "A", "project": "p", "w": 1}"#
        #expect(RemoteUsage.sourceErrors(Data(body.utf8), host: "my-vps") == "my-vps: Hermes: OperationalError")
        #expect(RemoteUsage.sourceErrors(Data(#"{"d": 1, "app": "A", "w": 1}"#.utf8), host: "my-vps") == nil)
    }

    @Test("The remote command carries no setting; extra folders must be absolute")
    func remoteCommandIsStatic() {
        #expect(!RemoteUsage.remoteCommand.contains("CONFIG"))
        let host = RemoteUsage.Host(alias: "my-vps", extraPaths: ["/srv/apps", " /data ", "relative", "/a\nb", ""])
        #expect(host.searchPaths == ["/srv/apps", "/data"])
        let script = RemoteUsage.script(since: Date(timeIntervalSince1970: 100), accountID: "acct", paths: ["/x'; rm"])
        let line = String(script.prefix { $0 != "\n" })
        #expect(line.hasPrefix("CONFIG_B64 = \"") && !line.contains("'"))
    }

    @Test("Found summary reads counts, unreadable folders and truncation")
    func foundSummary() {
        let data = Data(#"{"found": {"codex": 2, "hermes": 1, "usage_files": 0, "unreadable": 3, "truncated": true}}"#.utf8)
        let found = RemoteUsage.found(data)
        #expect(found?.summary == "2 Codex homes · 1 Hermes · 3 unreadable without sudo · search stopped early")
        #expect(RemoteUsage.Found().summary == "No Codex data found")
        #expect(RemoteUsage.found(Data("{}".utf8)) == nil)
    }

    @Test("Hosts saved as a comma list are migrated, then stored as JSON")
    func hostMigration() {
        let defaults = UserDefaults.standard
        let saved = (defaults.string(forKey: "usageSSHHosts"), defaults.string(forKey: "usageRemoteHosts"))
        defer {
            defaults.set(saved.0, forKey: "usageSSHHosts")
            defaults.set(saved.1, forKey: "usageRemoteHosts")
        }
        defaults.set("", forKey: "usageSSHHosts")
        defaults.set(" my-vps, other ,my-vps", forKey: "usageRemoteHosts")
        let settings = AppSettings()
        #expect(settings.remoteHosts.map(\.alias) == ["my-vps", "other"])
        var hosts = settings.remoteHosts
        hosts[1].enabled = false
        settings.remoteHosts = hosts
        #expect(settings.remoteHosts.map(\.enabled) == [true, false])
        #expect(defaults.string(forKey: "usageRemoteHosts") == "")
    }

    @Test("Collector finds Codex data by content, keeps the local account and skips copies")
    func collectorRun() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("collector-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let auth = #"{"tokens": {"account_id": "acct"}}"#
        let session = [
            #"{"type": "session_meta", "payload": {"id": "th1", "cwd": "/work/project-a"}}"#,
            #"{"type": "event_msg", "timestamp": "2026-10-20T10:00:00Z", "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 1000, "cached_input_tokens": 0, "output_tokens": 100}}}}"#,
        ].joined(separator: "\n")
        // A service's CODEX_HOME, and a backup copy of the same session
        try write("srv/service-a/state/auth.json", auth)
        try write("srv/service-a/state/sessions/2026/10/20/rollout-1.jsonl", session)
        try write("srv/backups/service-a/state/auth.json", auth)
        try write("srv/backups/service-a/state/sessions/2026/10/20/rollout-1.jsonl", session)
        // codex exec --ephemeral service: no account (counted, single account on host), another account (skipped)
        try write("srv/service-b/codex-usage.jsonl", [
            #"{"ts": "2026-10-20T11:00:00Z", "input_tokens": 200, "cached_input_tokens": 100, "output_tokens": 10, "project": "daily"}"#,
            #"{"ts": 1792490400, "input_tokens": 999, "output_tokens": 999, "account_id": "someone-else"}"#,
            #"{"ts": "2026-01-01T00:00:00Z", "input_tokens": 999, "output_tokens": 999}"#,
            "not json",
        ].joined(separator: "\n"))
        try write("srv/node_modules/x/codex-usage.jsonl", #"{"ts": "2026-10-20T11:00:00Z", "input_tokens": 5}"#)

        let since = ISO8601DateFormatter().date(from: "2026-10-19T00:00:00Z")!
        let script = RemoteUsage.script(since: since, accountID: "acct", paths: [], roots: [[root.path + "/srv", 6]])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", "-"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(RemoteUsage.sourceErrors(data, host: "h") == nil)
        let found = try #require(RemoteUsage.found(data))
        #expect(found.codexHomes == 2 && found.usageFiles == 1 && found.hermes == 0)
        let records = RemoteUsage.parse(data, host: "h").sorted { $0.date < $1.date }
        #expect(records.map(\.app) == ["h · service-a", "h · service-b"])
        #expect(records.map(\.project) == ["h:/project-a", "h:/daily"])
        #expect(records.map(\.weight) == [1500, 160])
    }

    @Test("Collector keeps the most complete copy, isolates bad lines, honours extra folders and login vetoes")
    func collectorEdgeCases() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("collector-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        func write(_ path: String, _ text: String) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        func session(_ input: Int) -> String {
            [#"{"type": "session_meta", "payload": {"id": "th1", "cwd": "/work/project-a"}}"#,
             #"{"type": "event_msg", "timestamp": "2026-10-20T10:00:00Z", "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": \#(input), "output_tokens": 0}}}}"#]
                .joined(separator: "\n")
        }
        let auth = #"{"tokens": {"account_id": "acct"}}"#
        try write("srv/live/home/auth.json", auth)
        try write("srv/live/home/sessions/rollout-1.jsonl", session(1000))
        // Written last, so newest: a partial backup must not replace the live session.
        try write("srv/backup/home/auth.json", auth)
        try write("srv/backup/home/sessions/rollout-1.jsonl", session(100))
        // Deeper than the default depth: reached only through an extra folder.
        try write("srv/a/b/c/d/e/f/svc/codex-usage.jsonl", [
            #"{"ts": "not a date", "input_tokens": 5, "account_id": "acct"}"#,
            #"{"ts": "2026-10-20T11:00:00Z", "input_tokens": 7, "account_id": "acct", "id": "c1"}"#,
            #"{"ts": "2026-10-20T11:00:00Z", "input_tokens": 7, "account_id": "acct", "id": "c2"}"#,
        ].joined(separator: "\n"))

        func run(_ roots: [[Any]], paths: [String] = []) throws -> Data {
            let since = ISO8601DateFormatter().date(from: "2026-10-19T00:00:00Z")!
            let script = RemoteUsage.script(since: since, accountID: "acct", paths: paths, roots: roots)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-I", "-"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            input.fileHandleForWriting.write(Data(script.utf8))
            try input.fileHandleForWriting.close()
            defer { process.waitUntilExit() }
            return output.fileHandleForReading.readDataToEndOfFile()
        }

        let srv = root.path + "/srv"
        let data = try run([[srv, 3]], paths: [srv + "/a/b/c/d/e/f"])
        let records = RemoteUsage.parse(data, host: "h")
        #expect(records.filter { $0.app == "h · live" || $0.app == "h · backup" }.map(\.weight) == [1000])
        #expect(records.filter { $0.app == "h · svc" }.map(\.weight) == [7, 7])
        #expect(RemoteUsage.sourceErrors(data, host: "h") == nil)

        // An account-less usage line is not counted when another login exists on the host.
        try write("srv/other/home/auth.json", #"{"tokens": {"account_id": "someone-else"}}"#)
        try write("srv/svc2/codex-usage.jsonl", #"{"ts": "2026-10-20T11:00:00Z", "input_tokens": 9}"#)
        let vetoed = RemoteUsage.parse(try run([[srv, 3]]), host: "h")
        #expect(!vetoed.contains { $0.app == "h · svc2" })
    }
}
