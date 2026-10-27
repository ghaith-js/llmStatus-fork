import Foundation

/// One subscription whose limits are shown: the login of this Mac, or a login on an SSH host.
struct UsageAccount: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Shown in the popover, e.g. "Claude · Client A".
    var name: String
    var kind: SubscriptionUsage.Kind
    /// SSH alias holding the login; nil for this Mac's own Claude Code / Codex login.
    var host: String?
    /// Folder of the login on the host (CLAUDE_CONFIG_DIR / CODEX_HOME); nil for ~/.claude or ~/.codex.
    var folder: String?
    var enabled = true

    var isLocal: Bool { host == nil }

    /// Where the limits come from; a row read from another source is stale.
    var source: String { [kind.rawValue, host ?? "", folder ?? ""].joined(separator: "|") }

    /// Where the login lives, for Settings.
    var location: String {
        guard let host else { return "This Mac" }
        return folder.map { "\(host):\($0)" } ?? host
    }
}

/// A named set of accounts, e.g. "Personal" or "Client A".
struct UsageGroup: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var accounts: [UsageAccount] = []

    /// First launch, or settings from before groups: this Mac's logins, hidden ones switched off.
    static func defaults(hidden: Set<SubscriptionUsage.Kind> = []) -> [UsageGroup] {
        [UsageGroup(name: "Personal", accounts: SubscriptionUsage.Kind.allCases.map {
            UsageAccount(name: $0.name, kind: $0, enabled: !hidden.contains($0))
        })]
    }
}
