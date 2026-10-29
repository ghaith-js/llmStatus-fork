import Foundation

/// Checks a server over SSH: reachability and answer time, disk space and inodes, memory, load,
/// failed systemd units, plus the services, Docker containers and ports listed in Settings.
/// A read-only POSIX sh script goes over stdin (`ssh -o BatchMode=yes`, `sudo -n` when allowed),
/// so nothing needs Python on the server and no value travels in the remote command.
enum ServerChecker {
    static let remoteCommand = "cd / && if sudo -n true 2>/dev/null; then exec sudo -n /bin/sh -s; else exec /bin/sh -s; fi"

    /// Answers slower than this are shown as degraded.
    static let slowSSH: TimeInterval = 5

    static func check(_ server: ServerMonitor) async -> CheckResult {
        let first = await Task.detached { run(server) }.value
        guard first.status.severity >= 3, first.items.count == 1 else { return first }
        // Unreachable: try once more before alerting.
        try? await Task.sleep(for: .seconds(3))
        return await Task.detached { run(server) }.value
    }

    /// The listed names are validated again here: only safe ones reach the script.
    static func script(for server: ServerMonitor) -> String {
        let services = server.services.filter(ServerMonitor.isSafeName).joined(separator: " ")
        let containers = server.containers.filter(ServerMonitor.isSafeName).joined(separator: " ")
        let ports = server.ports.filter { (1...65535).contains($0) }.map(String.init).joined(separator: " ")
        return "SERVICES='\(services)'\nCONTAINERS='\(containers)'\nPORTS='\(ports)'\n" + probe
    }

    private static func run(_ server: ServerMonitor) -> CheckResult {
        guard RemoteUsage.isValidHost(server.alias) else {
            return unreachable("Invalid SSH alias")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=5",
                             "--", server.alias, remoteCommand]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let start = Date()
        do { try process.run() } catch { return unreachable("ssh unavailable") }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            if process.isRunning { process.terminate() }
        }
        input.fileHandleForWriting.write(Data(script(for: server).utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let elapsed = Date().timeIntervalSince(start)
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0, text.contains("ok|end") else {
            let reason = sshReason(String(decoding: stderr, as: UTF8.self), status: process.terminationStatus)
            FileLogger.shared.warning("ssh \(server.alias): \(reason)", source: "ServerChecker")
            return unreachable(reason)
        }
        return evaluate(text, elapsed: elapsed, server: server)
    }

    private static func unreachable(_ reason: String) -> CheckResult {
        CheckResult(status: .critical, summary: reason, items: [CheckItem(name: "SSH", status: .critical, value: reason)])
    }

    /// A short reason from ssh's error output.
    static func sshReason(_ stderr: String, status: Int32) -> String {
        let text = stderr.lowercased()
        if text.contains("permission denied") { return "SSH login refused (key?)" }
        if text.contains("could not resolve") { return "Host not found (DNS)" }
        if text.contains("timed out") { return "SSH timed out" }
        if text.contains("connection refused") { return "SSH connection refused" }
        if text.contains("host key verification failed") { return "Host key not trusted yet" }
        if text.contains("no route") || text.contains("unreachable") { return "Network unreachable" }
        return status == 15 ? "Check timed out" : "Unreachable over SSH"
    }

    // MARK: - Evaluation

    static func evaluate(_ output: String, elapsed: TimeInterval, server: ServerMonitor) -> CheckResult {
        var items: [CheckItem] = []
        items.append(CheckItem(name: "SSH", status: elapsed > slowSSH ? .degraded : .operational,
                               value: String(format: "%.1f s", elapsed)))
        var maxDisk = 0
        var failedUnits: [String] = []
        let listed = Set(server.services)

        for line in output.split(separator: "\n") {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 2 else { continue }
            switch f[0] {
            case "disk" where f.count >= 4:
                guard let pct = Int(f[2]) else { continue }
                maxDisk = max(maxDisk, pct)
                let free = Double(f[3]).map { formatKB($0) + " free" }
                items.append(CheckItem(name: "Disk \(f[1])", status: level(pct, server),
                                       value: ["\(pct)%", free].compactMap { $0 }.joined(separator: " · ")))
            case "inode" where f.count >= 3:
                // Only worth a line when it gets close to full.
                guard let pct = Int(f[2]), pct >= server.diskWarn else { continue }
                items.append(CheckItem(name: "Inodes \(f[1])", status: level(pct, server), value: "\(pct)%"))
            case "mem" where f.count >= 2:
                guard let free = Int(f[1]) else { continue }
                let status: ServiceStatus = free < 5 ? .majorOutage : free < 10 ? .degraded : .operational
                items.append(CheckItem(name: "Memory", status: status, value: "\(free)% available"))
            case "load" where f.count >= 3:
                guard let load = Double(f[1]), let cpus = Int(f[2]), cpus > 0 else { continue }
                let perCPU = load / Double(cpus)
                let status: ServiceStatus = perCPU > 4 ? .majorOutage : perCPU > 2 ? .degraded : .operational
                items.append(CheckItem(name: "Load", status: status,
                                       value: String(format: "%.2f · %d CPU%@", load, cpus, cpus > 1 ? "s" : "")))
            case "uptime":
                guard let seconds = Int(f[1]) else { continue }
                items.append(CheckItem(name: "Uptime", status: .operational, value: formatDuration(seconds)))
            case "unit" where f.count >= 3:
                let state = f[2].isEmpty ? "unknown" : f[2]
                let status: ServiceStatus = switch state {
                case "active": .operational
                case "activating", "reloading": .degraded
                default: .critical
                }
                items.append(CheckItem(name: f[1], status: status, value: state == "nosystemd" ? "No systemd" : state))
            case "failed":
                // Leftovers of systemd-run (run-u123.service) stay failed until reset: not a service down.
                if f[1].range(of: #"^run-[ru][0-9a-f]+\.(service|scope)$"#, options: .regularExpression) != nil { continue }
                let unit = f[1].hasSuffix(".service") ? String(f[1].dropLast(8)) : f[1]
                if !listed.contains(unit) && !listed.contains(f[1]) { failedUnits.append(unit) }
            case "container" where f.count >= 3:
                let parts = f[2].split(separator: "/").map(String.init)
                let state = parts.first ?? "missing", health = parts.count > 1 ? parts[1] : nil
                let status: ServiceStatus
                if state != "running" { status = .critical }
                else if health == "unhealthy" { status = .majorOutage }
                else if health == "starting" { status = .degraded }
                else { status = .operational }
                let value = state == "nodocker" ? "Docker not found" : state == "missing" ? "Not found"
                    : [state, health].compactMap { $0 }.joined(separator: " · ")
                items.append(CheckItem(name: "🐳 \(f[1])", status: status, value: value))
            case "port" where f.count >= 3:
                items.append(CheckItem(name: "Port \(f[1])", status: f[2] == "open" ? .operational : .critical,
                                       value: f[2] == "open" ? "Listening" : f[2] == "unknown" ? "Cannot tell (no ss/netstat)" : "Not listening"))
            default:
                continue
            }
        }
        for unit in failedUnits {
            items.append(CheckItem(name: unit, status: .majorOutage, value: "failed"))
        }
        let status = CheckResult.worst(items)
        let load = items.first { $0.name == "Load" }?.value.split(separator: " ").first.map(String.init)
        let summary = ["Disk \(maxDisk)%", load.map { "load \($0)" }].compactMap { $0 }.joined(separator: " · ")
        return CheckResult(status: status, summary: summary, items: items)
    }

    private static func level(_ pct: Int, _ server: ServerMonitor) -> ServiceStatus {
        pct >= server.diskCritical ? .critical : pct >= server.diskWarn ? .degraded : .operational
    }

    static func formatKB(_ kb: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(kb * 1024), countStyle: .file)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }

    /// Read-only probe. Prints `kind|name|value...` lines and `ok|end` when it got to the end.
    static let probe = #"""
    export LC_ALL=C
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    skip='^(/proc|/sys|/dev|/run|/snap|/var/lib/docker|/boot/efi)'
    { df -P -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null || df -P 2>/dev/null; } |
      awk -v s="$skip" 'NR>1 && $6 !~ s && !seen[$6]++ { gsub("%","",$5); print "disk|"$6"|"$5"|"$4 }'
    { df -Pi -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null || df -Pi 2>/dev/null; } |
      awk -v s="$skip" 'NR>1 && $6 !~ s && !seen[$6]++ { gsub("%","",$5); print "inode|"$6"|"$5 }'
    if [ -r /proc/meminfo ]; then
      awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{ if (t>0) printf "mem|%d\n", a*100/t }' /proc/meminfo
    fi
    if [ -r /proc/loadavg ]; then
      cpus=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
      echo "load|$(cut -d' ' -f1 /proc/loadavg)|$cpus"
    fi
    [ -r /proc/uptime ] && echo "uptime|$(cut -d. -f1 /proc/uptime)"
    if command -v systemctl >/dev/null 2>&1; then
      for u in $SERVICES; do echo "unit|$u|$(systemctl is-active "$u" 2>/dev/null | head -n1)"; done
      systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '$1 != "" {print "failed|"$1}'
    else
      for u in $SERVICES; do echo "unit|$u|nosystemd"; done
    fi
    if [ -n "$CONTAINERS" ]; then
      if command -v docker >/dev/null 2>&1; then
        for c in $CONTAINERS; do
          s=$(docker inspect -f '{{.State.Status}}{{if .State.Health}}/{{.State.Health.Status}}{{end}}' "$c" 2>/dev/null)
          echo "container|$c|${s:-missing}"
        done
      else
        for c in $CONTAINERS; do echo "container|$c|nodocker"; done
      fi
    fi
    if [ -n "$PORTS" ]; then
      if command -v ss >/dev/null 2>&1; then
        listening=$(ss -ltn 2>/dev/null | awk 'NR>1 {print $4}')
      elif command -v netstat >/dev/null 2>&1; then
        listening=$(netstat -ltn 2>/dev/null | awk 'NR>2 {print $4}')
      else
        listening=none
      fi
      for p in $PORTS; do
        if [ "$listening" = none ]; then echo "port|$p|unknown"
        elif echo "$listening" | grep -Eq "[:.]$p\$"; then echo "port|$p|open"
        else echo "port|$p|closed"; fi
      done
    fi
    echo "ok|end"
    """#
}
