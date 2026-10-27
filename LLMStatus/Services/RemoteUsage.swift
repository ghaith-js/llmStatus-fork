import Foundation

/// Codex usage spent on other machines reachable over SSH (e.g. a VPS running Hermes or
/// services calling `codex exec`). A read-only Python collector runs remotely and returns token
/// totals only: no conversation content and no credential leaves the host.
enum RemoteUsage {
    struct Result {
        var records: [UsageBreakdown.Record] = []
        /// Set when the host could not be read; shown under the breakdown.
        var error: String?
    }

    /// SSH alias or user@host: no option-looking or shell-meaningful characters.
    static func isValidHost(_ host: String) -> Bool {
        !host.hasPrefix("-") && host.range(of: #"^[A-Za-z0-9._@-]+$"#, options: .regularExpression) != nil
    }

    static func fetch(host: String, since start: Date, accountID: String?) -> Result {
        guard isValidHost(host) else { return Result(error: "\(host): invalid host") }
        // Without the local account, remote usage of any account would be counted.
        guard let accountID, accountID.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            return Result(error: "\(host): local Codex account unknown")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        let args = "\(Int(start.timeIntervalSince1970)) \(accountID)"
        // Service data is usually root-owned; fall back to the login user without sudo.
        // -I and cd /: no module from the login directory can shadow the collector's imports.
        let python = "/usr/bin/python3 -I - \(args)"
        let remote = "cd / && if sudo -n true 2>/dev/null; then exec sudo -n \(python); else exec \(python); fi"
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "--", host, remote]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return Result(error: "\(host): ssh unavailable") }
        input.fileHandleForWriting.write(Data(collector.utf8))
        try? input.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            if process.isRunning { process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            FileLogger.shared.warning("ssh \(host) exited \(process.terminationStatus)", source: "RemoteUsage")
            return Result(error: "\(host) unreachable")
        }
        return Result(records: parse(data, host: host), error: sourceErrors(data, host: host))
    }

    /// Sources the collector could not read (`{"error": ...}` lines), so they are not shown as zero usage.
    static func sourceErrors(_ data: Data, host: String) -> String? {
        let errors = data.split(separator: UInt8(ascii: "\n")).compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])?["error"] as? String
        }
        return errors.isEmpty ? nil : "\(host): " + errors.joined(separator: "; ")
    }

    /// One JSON object per line: {"d": epoch, "app", "project", "w": weight, "t": thread, "p": parent}.
    static func parse(_ data: Data, host: String) -> [UsageBreakdown.Record] {
        data.split(separator: UInt8(ascii: "\n")).compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let epoch = (object["d"] as? NSNumber)?.doubleValue,
                  let app = object["app"] as? String,
                  let weight = (object["w"] as? NSNumber)?.doubleValue, weight > 0
            else { return nil }
            return UsageBreakdown.Record(
                date: Date(timeIntervalSince1970: epoch),
                app: "\(host) · \(app)",
                // Remote paths must not merge with local ones of the same name.
                project: "\(host):/\(object["project"] as? String ?? "Unknown")",
                weight: weight,
                thread: object["t"] as? String,
                parentThread: object["p"] as? String
            )
        }
    }

    /// Runs on the remote host with `python3 -I - <since epoch> <ChatGPT account id>`.
    /// Same weighting as the local scan: uncached input + 0.1 × cached input + 5 × output.
    static let collector = #"""
import base64, glob, json, os, sqlite3, sys

since = float(sys.argv[1])
account = sys.argv[2]

def emit(d, app, project, w, t=None, p=None):
    if w > 0:
        print(json.dumps({"d": d, "app": app, "project": project, "w": w, "t": t, "p": p}))

def jwt_account(token):
    try:
        claims = json.loads(base64.urlsafe_b64decode(token.split(".")[1] + "=="))
        return claims.get("https://api.openai.com/auth", {}).get("chatgpt_account_id")
    except Exception:
        return None

def fail(source, exc):
    print(json.dumps({"error": source + ": " + type(exc).__name__}))

def epoch(ts):
    from datetime import datetime
    return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()

def project_of(cwd):
    return os.path.basename(cwd.rstrip("/")) if cwd else "Unknown"

# Codex homes: users' ~/.codex and "codex-home" folders mounted as CODEX_HOME by containerized services
homes = glob.glob("/home/*/.codex") + glob.glob("/root/.codex") \
    + glob.glob("/home/*/*/codex-home") + glob.glob("/home/*/*/*/codex-home")
for home in homes:
    parent = os.path.basename(os.path.dirname(home))
    label = parent if home.endswith("codex-home") else "Codex"
    try:
        tokens = json.load(open(os.path.join(home, "auth.json"))).get("tokens") or {}
    except FileNotFoundError:
        continue
    except Exception as exc:
        fail(label, exc)
        continue
    current = tokens.get("account_id")
    for path in glob.glob(os.path.join(home, "sessions", "**", "*.jsonl"), recursive=True):
      try:
        if os.path.getmtime(path) < since:
            continue
        app, project, thread, spawn, previous = label, "Unknown", None, None, 0.0
        mine = True
        for line in open(path, errors="replace"):
            if '"session_meta"' not in line and '"token_count"' not in line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                continue
            pl = o.get("payload") or {}
            if o.get("type") == "session_meta":
                # A session belongs to the account that created it, not to the home's current login.
                mine = (pl.get("creator_account_id") or current) == account
                project, thread = project_of(pl.get("cwd")), pl.get("id")
                src = pl.get("source")
                sub = src.get("subagent") if isinstance(src, dict) else None
                ts = sub.get("thread_spawn") if isinstance(sub, dict) else None
                spawn = ts.get("parent_thread_id") if isinstance(ts, dict) else None
                continue
            total = ((pl.get("info") or {}).get("total_token_usage")) if pl.get("type") == "token_count" else None
            if not mine or not total or "timestamp" not in o:
                continue
            cached = total.get("cached_input_tokens", 0) or 0
            cumulative = (total.get("input_tokens", 0) - cached) + 0.1 * cached + 5 * (total.get("output_tokens", 0) or 0)
            if cumulative > previous:
                d = epoch(o["timestamp"])
                if d >= since:
                    emit(d, app, project, cumulative - previous, thread, spawn)
                previous = cumulative
      except Exception as exc:
        fail(label, exc)

# Hermes agents calling the Codex subscription directly (no Codex session files)
for db in glob.glob("/home/*/.hermes/state.db") + glob.glob("/home/*/*/*/data/state.db"):
    auth = os.path.join(os.path.dirname(db), "auth.json")
    try:
        pool = json.load(open(auth)).get("credential_pool", {}).get("openai-codex") or []
        # Rows carry no account: count them only when every Codex credential is the local account.
        if not pool or any(jwt_account(c.get("access_token", "")) != account for c in pool):
            continue
        con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
        rows = con.execute(
            "select u.first_seen, u.last_seen, coalesce(s.source, ''), coalesce(u.task, ''),"
            " u.input_tokens, u.cache_read_tokens, u.output_tokens"
            " from session_model_usage u left join sessions s on s.id = u.session_id"
            " where u.billing_provider = 'openai-codex' and u.last_seen >= ?", (since,)).fetchall()
    except Exception as exc:
        fail("Hermes", exc)
        continue
    for first_seen, last_seen, source, task, inp, cache_read, out in rows:
        project = source or "Hermes"
        if task:
            project += " (" + task.replace("_", " ") + ")"
        weight = (inp or 0) + 0.1 * (cache_read or 0) + 5 * (out or 0)
        # Counters are cumulative per session: keep the share of its span inside the window.
        if first_seen and first_seen < since < last_seen:
            weight *= (last_seen - since) / (last_seen - first_seen)
        emit(last_seen, "Hermes", project, weight)
"""#
}
