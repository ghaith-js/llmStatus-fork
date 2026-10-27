import Foundation

/// Limits of a Claude or ChatGPT (Codex) login that lives on an SSH host. The usage API is called
/// from the host itself, so its token never leaves it; only the limits come back.
enum RemoteAccountUsage {
    /// Login user's name is passed so the script finds that user's home even under sudo.
    static let remoteCommand = #"cd / && U=$(id -un) && if sudo -n true 2>/dev/null; "#
        + #"then exec sudo -n /usr/bin/python3 -I - "$U"; else exec /usr/bin/python3 -I - "$U"; fi"#

    /// Absolute, or in the login user's home ("~/..."). Sent inside the script, never in the command.
    static func isValidFolder(_ folder: String) -> Bool {
        (folder.hasPrefix("/") || folder.hasPrefix("~/")) && !folder.contains(where: \.isNewline)
    }

    static func script(for account: UsageAccount) -> String {
        var config: [String: Any] = ["kind": account.kind.rawValue]
        if let folder = account.folder { config["folder"] = folder }
        let json = (try? JSONSerialization.data(withJSONObject: config)) ?? Data("{}".utf8)
        return "CONFIG_B64 = \"\(json.base64EncodedString())\"\n" + collector
    }

    static func fetch(_ account: UsageAccount) -> SubscriptionUsage {
        var usage = SubscriptionUsage(kind: account.kind, accountID: account.id, title: account.name)
        guard let host = account.host, RemoteUsage.isValidHost(host) else {
            usage.error = "Invalid SSH host"
            return usage
        }
        if let folder = account.folder, !isValidFolder(folder) {
            usage.error = "Invalid folder"
            return usage
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "--", host, remoteCommand]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            usage.error = "ssh unavailable"
            return usage
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            if process.isRunning { process.terminate() }
        }
        input.fileHandleForWriting.write(Data(script(for: account).utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            FileLogger.shared.warning("ssh \(host) exited \(process.terminationStatus)", source: "RemoteAccountUsage")
            usage.error = "\(host) unreachable"
            return usage
        }
        return parse(data, into: usage, host: host)
    }

    /// The script prints one JSON object: {"status", "plan", "body"} or {"error", "folder"?, "plan"?}.
    static func parse(_ data: Data, into base: SubscriptionUsage, host: String) -> SubscriptionUsage {
        var usage = base
        let line = data.split(separator: UInt8(ascii: "\n")).last.map { Data($0) } ?? Data()
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            usage.error = "Unreadable answer from \(host)"
            return usage
        }
        let cli = usage.kind == .claude ? "claude" : "codex"
        if let plan = object["plan"] as? String { usage.plan = plan.capitalized }
        if let error = object["error"] as? String {
            let folder = object["folder"] as? String ?? "?"
            usage.error = switch error {
            case "missing": "No \(usage.kind.name) login in \(folder) on \(host)"
            case "unreadable": "Cannot read \(folder) on \(host)"
            case "expired": "Token expired on \(host), run \(cli) there"
            default: "Usage unavailable from \(host)"
            }
            return usage
        }
        let status = (object["status"] as? NSNumber)?.intValue ?? 0
        if status == 401 || status == 403 {
            usage.error = "Session expired on \(host), run \(cli) there"
            return usage
        }
        guard (200...299).contains(status), let body = object["body"],
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            usage.error = "Usage unavailable (HTTP \(status))"
            return usage
        }
        let plan = usage.plan
        usage = usage.kind == .claude ? UsageFetcher.parseClaude(bodyData, into: usage) : UsageFetcher.parseCodex(bodyData, into: usage)
        if usage.plan == nil { usage.plan = plan }
        return usage
    }

    /// Runs on the host with `python3 -I - <login user>`, after a `CONFIG_B64 = "..."` line.
    /// Reads the login file, calls the usage API with it, and prints the limits only.
    static let collector = #"""
import base64, json, os, pwd, sys, time, urllib.error, urllib.request

CONFIG = json.loads(base64.b64decode(CONFIG_B64))
kind = CONFIG["kind"]
home = pwd.getpwnam(sys.argv[1]).pw_dir if len(sys.argv) > 1 else os.path.expanduser("~")
folder = CONFIG.get("folder") or ("~/.claude" if kind == "claude" else "~/.codex")
if folder.startswith("~/"):
    folder = os.path.join(home, folder[2:])
elif not folder.startswith("/"):
    out(error="unreadable", folder=folder)

def out(**fields):
    print(json.dumps(fields))
    sys.exit(0)

def load(name):
    try:
        with open(os.path.join(folder, name)) as f:
            return json.load(f)
    except FileNotFoundError:
        out(error="missing", folder=folder)
    except Exception:
        out(error="unreadable", folder=folder)

def call(url, headers):
    headers["User-Agent"] = "llm-status"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=15) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        return exc.code, None
    except Exception as exc:
        out(error="network")

if kind == "claude":
    oauth = (load(".credentials.json") or {}).get("claudeAiOauth") or {}
    if not oauth.get("accessToken"):
        out(error="missing", folder=folder)
    plan = oauth.get("subscriptionType")
    if oauth.get("expiresAt") and oauth["expiresAt"] / 1000 < time.time():
        out(error="expired", plan=plan)
    status, body = call("https://api.anthropic.com/api/oauth/usage",
                        {"Authorization": "Bearer " + oauth["accessToken"], "anthropic-beta": "oauth-2025-04-20"})
    keep = ("five_hour", "seven_day")
else:
    tokens = (load("auth.json") or {}).get("tokens") or {}
    if not tokens.get("access_token"):
        out(error="missing", folder=folder)
    headers = {"Authorization": "Bearer " + tokens["access_token"]}
    if tokens.get("account_id"):
        headers["ChatGPT-Account-Id"] = tokens["account_id"]
    status, body = call("https://chatgpt.com/backend-api/wham/usage", headers)
    plan, keep = None, ("plan_type", "rate_limit")
# Only the limits: the API also returns the account's email and ids.
out(status=status, plan=plan, body={k: body.get(k) for k in keep} if isinstance(body, dict) else None)
"""#
}
