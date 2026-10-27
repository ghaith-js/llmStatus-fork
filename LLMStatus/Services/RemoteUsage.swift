import Foundation

/// Codex usage spent on other machines reachable over SSH (e.g. a VPS running Hermes or
/// services calling `codex exec`). A read-only Python collector runs remotely and returns token
/// totals with app and project names only: no conversation content and no credential leaves the host.
enum RemoteUsage {
    /// One SSH host set up in Settings.
    struct Host: Codable, Hashable, Identifiable {
        var id = UUID()
        /// SSH alias from ~/.ssh/config, or user@host.
        var alias: String
        var enabled = true
        /// Folders searched in addition to the usual ones (/home, /root, /srv, /opt, Docker volumes).
        var extraPaths: [String] = []

        /// Absolute folders only; anything else is ignored rather than sent.
        var searchPaths: [String] {
            extraPaths.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("/") && !$0.contains("\n") }
        }
    }

    /// What the collector found on a host, shown in Settings.
    struct Found: Equatable {
        var codexHomes = 0
        var hermes = 0
        var usageFiles = 0
        /// Folders that looked relevant but could not be read (no passwordless sudo).
        var unreadable = 0
        /// The search hit its time budget; some folders were not visited.
        var truncated = false

        var summary: String {
            var parts = [Self.count(codexHomes, "Codex home"), Self.count(hermes, "Hermes", plural: "Hermes"),
                         Self.count(usageFiles, "usage file")].compactMap { $0 }
            if parts.isEmpty { parts.append("No Codex data found") }
            if unreadable > 0 { parts.append("\(unreadable) unreadable without sudo") }
            if truncated { parts.append("search stopped early") }
            return parts.joined(separator: " · ")
        }

        private static func count(_ n: Int, _ noun: String, plural: String? = nil) -> String? {
            n == 0 ? nil : "\(n) \(n > 1 ? plural ?? noun + "s" : noun)"
        }
    }

    struct Result {
        var records: [UsageBreakdown.Record] = []
        /// Set when the host could not be read; shown under the breakdown.
        var error: String?
        var found: Found?
    }

    /// Last check of a host, shown in Settings.
    struct Status: Equatable {
        var checkedAt: Date
        var error: String?
        var found: Found?

        init(_ result: Result, at date: Date = Date()) {
            checkedAt = date
            error = result.error
            found = result.found
        }
    }

    /// SSH alias or user@host: no option-looking or shell-meaningful characters.
    static func isValidHost(_ host: String) -> Bool {
        !host.hasPrefix("-") && host.range(of: #"^[A-Za-z0-9._@-]+$"#, options: .regularExpression) != nil
    }

    /// The remote command carries no data: settings travel inside the script on stdin.
    /// Service data is usually root-owned; fall back to the login user without sudo.
    /// -I and cd /: no module from the login directory can shadow the collector's imports.
    static let remoteCommand = "cd / && if sudo -n true 2>/dev/null; then exec sudo -n /usr/bin/python3 -I -; "
        + "else exec /usr/bin/python3 -I -; fi"

    /// Collector source with its settings prepended as base64 JSON, so no value needs quoting.
    /// `roots` replaces the default search folders (tests only).
    static func script(since start: Date, accountID: String, paths: [String], roots: [[Any]]? = nil) -> String {
        var config: [String: Any] = ["since": start.timeIntervalSince1970, "account": accountID, "paths": paths]
        if let roots { config["roots"] = roots }
        let json = (try? JSONSerialization.data(withJSONObject: config)) ?? Data("{}".utf8)
        return "CONFIG_B64 = \"\(json.base64EncodedString())\"\n" + collector
    }

    static func fetch(host: Host, since start: Date, accountID: String?) -> Result {
        let name = host.alias
        guard isValidHost(name) else { return Result(error: "\(name): invalid host") }
        // Without the local account, remote usage of any account would be counted.
        guard let accountID, accountID.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            return Result(error: "\(name): local Codex account unknown")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "--", name, remoteCommand]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return Result(error: "\(name): ssh unavailable") }
        DispatchQueue.global().asyncAfter(deadline: .now() + 45) {
            if process.isRunning { process.terminate() }
        }
        input.fileHandleForWriting.write(Data(script(since: start, accountID: accountID, paths: host.searchPaths).utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            FileLogger.shared.warning("ssh \(name) exited \(process.terminationStatus)", source: "RemoteUsage")
            return Result(error: "\(name) unreachable")
        }
        return Result(records: parse(data, host: name), error: sourceErrors(data, host: name), found: found(data))
    }

    /// Sources the collector could not read (`{"error": ...}` lines), so they are not shown as zero usage.
    static func sourceErrors(_ data: Data, host: String) -> String? {
        let errors = objects(data).compactMap { $0["error"] as? String }
        return errors.isEmpty ? nil : "\(host): " + errors.joined(separator: "; ")
    }

    /// The final `{"found": ...}` line; nil when the collector did not finish.
    static func found(_ data: Data) -> Found? {
        guard let object = objects(data).lazy.compactMap({ $0["found"] as? [String: Any] }).first else { return nil }
        func int(_ key: String) -> Int { (object[key] as? NSNumber)?.intValue ?? 0 }
        return Found(codexHomes: int("codex"), hermes: int("hermes"), usageFiles: int("usage_files"),
                     unreadable: int("unreadable"), truncated: object["truncated"] as? Bool ?? false)
    }

    /// One JSON object per line: {"d": epoch, "app", "project", "w": weight, "t": thread, "p": parent}.
    static func parse(_ data: Data, host: String) -> [UsageBreakdown.Record] {
        objects(data).compactMap { object in
            guard let epoch = (object["d"] as? NSNumber)?.doubleValue,
                  let app = object["app"] as? String,
                  let weight = (object["w"] as? NSNumber)?.doubleValue, weight > 0
            else { return nil }
            // On a host: Hermes, or the Codex CLI used by services (named first) and by users.
            let project = object["project"] as? String ?? "Unknown"
            let isCLI = app != "Hermes"
            let label = !isCLI || app == "Codex" || app == project ? project : "\(app) · \(project)"
            return UsageBreakdown.Record(
                date: Date(timeIntervalSince1970: epoch),
                app: isCLI ? UsageBreakdown.codexCLI : app,
                // Remote paths must not merge with local ones of the same name.
                project: "\(host):/\(label)",
                weight: weight,
                thread: object["t"] as? String,
                parentThread: object["p"] as? String,
                host: host
            )
        }
    }

    private static func objects(_ data: Data) -> [[String: Any]] {
        data.split(separator: UInt8(ascii: "\n")).compactMap {
            try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
        }
    }

    /// Runs on the remote host with `python3 -I -`, after a `CONFIG_B64 = "..."` line.
    /// Finds Codex data by content, not by folder name:
    /// - Codex homes: an `auth.json` holding ChatGPT `tokens`; their `sessions/**/*.jsonl` are read.
    /// - Hermes: an `auth.json` holding a `credential_pool`, next to `state.db`.
    /// - `codex-usage.jsonl`: one line per call, written by services running `codex exec --ephemeral`
    ///   (which leaves no session file). Format in the README.
    /// Same weighting as the local scan: uncached input + 0.1 × cached input + 5 × output.
    static let collector = #"""
import base64, json, os, sqlite3, time
from datetime import datetime

CONFIG = json.loads(base64.b64decode(CONFIG_B64))
since = float(CONFIG["since"])
account = CONFIG["account"]
# (folder, depth): users, services and Docker volumes, then the host's extra folders
roots = CONFIG.get("roots") or [["/home", 6], ["/root", 4], ["/srv", 5], ["/opt", 4], ["/var/lib/docker/volumes", 3]]
roots = roots + [[p, 6] for p in CONFIG.get("paths", [])]
PRUNE = {"node_modules", ".git", ".next", ".npm", ".pnpm-store", ".cargo", ".rustup", ".nvm", "__pycache__",
         "site-packages", ".venv", "venv", ".cache"}
deadline = time.time() + 25  # the app stops waiting at 45 s
found = {"codex": 0, "hermes": 0, "usage_files": 0, "unreadable": 0, "truncated": False}

def emit(d, app, project, w, t=None, p=None):
    if w > 0:
        print(json.dumps({"d": d, "app": app, "project": project, "w": w, "t": t, "p": p}))

def fail(source, exc):
    print(json.dumps({"error": source + ": " + type(exc).__name__}))

def out_of_time():
    if time.time() > deadline:
        found["truncated"] = True
    return found["truncated"]

def denied(exc):
    if isinstance(exc, PermissionError):
        found["unreadable"] += 1

def jwt_account(token):
    try:
        claims = json.loads(base64.urlsafe_b64decode(token.split(".")[1] + "=="))
        return claims.get("https://api.openai.com/auth", {}).get("chatgpt_account_id")
    except Exception:
        return None

def epoch(ts):
    if isinstance(ts, (int, float)) and not isinstance(ts, bool):
        return float(ts)
    return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp()

def number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 0 else 0

def project_of(cwd):
    return os.path.basename(cwd.rstrip("/")) if cwd else "Unknown"

def codex_label(home):
    # A user's own ~/.codex is "Codex"; a service's CODEX_HOME is named after the folder holding it.
    parent = os.path.dirname(home)
    if os.path.basename(home) == ".codex" and (os.path.dirname(parent) == "/home" or parent == "/root"):
        return "Codex"
    return os.path.basename(parent)

def service_label(path):
    parts = path.split("/")
    if path.startswith("/var/lib/docker/volumes/") and len(parts) > 5:
        return parts[5].split("_")[0]  # compose volumes are named "<project>_<volume>"
    return os.path.basename(os.path.dirname(path))

# Discovery. A folder is skipped only when an earlier root already searched it at least as deep.
codex_homes, hermes_dbs, usage_files, depth_left = [], [], [], {}
for root, max_depth in roots:
    base = root.rstrip("/").count("/")
    for folder, dirs, files in os.walk(root, onerror=denied):
        if out_of_time():
            break
        real = os.path.realpath(folder)
        left = max_depth - (folder.rstrip("/").count("/") - base)
        if depth_left.get(real, -1) >= left:
            dirs[:] = []
            continue
        first_visit = real not in depth_left
        depth_left[real] = left
        dirs[:] = [d for d in dirs if d not in PRUNE] if left > 0 else []
        if not first_visit:
            continue
        if "codex-usage.jsonl" in files:
            usage_files.append(os.path.join(folder, "codex-usage.jsonl"))
        if "auth.json" not in files:
            continue
        try:
            with open(os.path.join(folder, "auth.json")) as f:
                auth = json.load(f)
        except PermissionError:
            found["unreadable"] += 1
            continue
        except Exception:
            continue
        if not isinstance(auth, dict):
            continue
        if isinstance(auth.get("tokens"), dict):
            codex_homes.append((folder, auth["tokens"].get("account_id")))
            dirs[:] = []  # its sessions are read below
        elif isinstance(auth.get("credential_pool"), dict) and "state.db" in files:
            hermes_dbs.append((folder, auth))

found["codex"], found["hermes"], found["usage_files"] = len(codex_homes), len(hermes_dbs), len(usage_files)

# Backups and restore checks copy whole folders: each source below counts one copy of a session,
# call or row, the most complete one.
def read_session(path, current):
    """(final cumulative weight, events) of one rollout file, events already filtered to the account."""
    events, project, thread, spawn, previous, mine = [], "Unknown", None, None, 0.0, True
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
        if not isinstance(total, dict) or "timestamp" not in o:
            continue
        cached = number(total.get("cached_input_tokens"))
        cumulative = number(total.get("input_tokens")) - cached + 0.1 * cached + 5 * number(total.get("output_tokens"))
        if cumulative > previous:
            try:
                d = epoch(o["timestamp"])
            except Exception:
                continue
            if mine and d >= since:
                events.append((d, project, cumulative - previous, thread, spawn))
            previous = cumulative
    return previous, events

sessions = {}  # rollout file name (unique per session) -> (final weight, label, events)
for home, current in codex_homes:
    label = codex_label(home)
    for folder, _, files in os.walk(os.path.join(home, "sessions"), onerror=denied):
        if out_of_time():
            break
        for name in files:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(folder, name)
            try:
                if os.path.getmtime(path) < since:
                    continue
                final, events = read_session(path, current)
            except Exception as exc:
                denied(exc)
                fail(label, exc)
                continue
            if final > sessions.get(name, (-1,))[0]:
                sessions[name] = (final, label, events)
for _, label, events in sessions.values():
    for d, project, w, thread, spawn in events:
        emit(d, label, project, w, thread, spawn)

# A usage line without "account_id" counts only when every login found on the host (Codex homes
# and Hermes credentials) is the local account and no folder was unreadable.
logins = [a for _, a in codex_homes] + [jwt_account(c.get("access_token", ""))
          for _, auth in hermes_dbs for c in (auth["credential_pool"].get("openai-codex") or [])]
single_account = bool(logins) and all(a == account for a in logins) and found["unreadable"] == 0
calls = {}  # call identity -> file that counted it
for path in usage_files:
    if out_of_time():
        break
    label = service_label(path)
    try:
        if os.path.getmtime(path) < since:
            continue
        lines = open(path, errors="replace").readlines()
    except Exception as exc:
        denied(exc)
        fail(label, exc)
        continue
    for line in lines:
        try:
            o = json.loads(line)
            if not isinstance(o, dict) or "ts" not in o:
                continue
            owner = o.get("account_id")
            if owner != account and not (owner is None and single_account):
                continue
            d = epoch(o["ts"])
            if d < since:
                continue
            app, project = str(o.get("app") or label), str(o.get("project") or label)
            inp, cached, out = number(o.get("input_tokens")), number(o.get("cached_input_tokens")), number(o.get("output_tokens"))
            # "id" identifies a call; without it, an identical call seen in another file is a copy.
            key = o.get("id") or (d, app, project, inp, cached, out)
            if calls.setdefault(str(key), path) != path:
                continue
            emit(d, app, project, inp - cached + 0.1 * cached + 5 * out)
        except Exception:
            continue

# Hermes agents calling the Codex subscription directly (no Codex session files)
usage = {}  # (session, model, task) -> row with the latest last_seen
for folder, auth in hermes_dbs:
    try:
        pool = auth["credential_pool"].get("openai-codex") or []
        # Rows carry no account: count them only when every Codex credential is the local account.
        if not pool or any(jwt_account(c.get("access_token", "")) != account for c in pool):
            continue
        con = sqlite3.connect("file:" + os.path.join(folder, "state.db") + "?mode=ro", uri=True)
        rows = con.execute(
            "select u.session_id, u.model, u.first_seen, u.last_seen, coalesce(s.source, ''), coalesce(u.task, ''),"
            " u.input_tokens, u.cache_read_tokens, u.output_tokens"
            " from session_model_usage u left join sessions s on s.id = u.session_id"
            " where u.billing_provider = 'openai-codex' and u.last_seen >= ?", (since,)).fetchall()
    except Exception as exc:
        denied(exc)
        fail("Hermes", exc)
        continue
    for row in rows:
        key = row[:2] + row[5:6]
        if key not in usage or (row[3] or 0) > (usage[key][3] or 0):
            usage[key] = row
for _, _, first_seen, last_seen, source, task, inp, cache_read, out in usage.values():
    project = source or "Hermes"
    if task:
        project += " (" + task.replace("_", " ") + ")"
    weight = (inp or 0) + 0.1 * (cache_read or 0) + 5 * (out or 0)
    # Counters are cumulative per session: keep the share of its span inside the window.
    if first_seen and first_seen < since < last_seen:
        weight *= (last_seen - since) / (last_seen - first_seen)
    emit(last_seen, "Hermes", project, weight)

print(json.dumps({"found": found}))
"""#
}
