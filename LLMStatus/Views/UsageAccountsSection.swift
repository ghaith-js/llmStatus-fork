import SwiftUI

/// Settings sections for the subscriptions shown in the popover: named groups of accounts,
/// each logged in on this Mac or on an SSH host. Every change syncs right away.
struct UsageAccountsSection: View {
    @Bindable var settings: AppSettings
    var usage: UsageMonitor
    @State private var groups: [UsageGroup] = []
    /// Account or group whose editor opens as soon as it is added.
    @State private var justAdded: UUID?

    var body: some View {
        Group {
            ForEach($groups) { $group in
                Section {
                    ForEach($group.accounts) { $account in
                        UsageAccountRow(
                            account: $account,
                            usage: usage.usages.first { $0.accountID == account.id },
                            startEditing: justAdded == account.id,
                            onRemove: { group.accounts.removeAll { $0.id == account.id }; sync() },
                            onCommit: sync
                        )
                    }
                    Button {
                        let account = UsageAccount(name: "Claude", kind: .claude, host: "")
                        group.accounts.append(account)
                        justAdded = account.id
                    } label: {
                        Label("Add account", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                } header: {
                    UsageGroupHeader(
                        group: $group,
                        startEditing: justAdded == group.id,
                        canRemove: groups.count > 1,
                        onRemove: { groups.removeAll { $0.id == group.id }; sync() },
                        onCommit: sync
                    )
                }
            }

            Section {
                Button {
                    let group = UsageGroup(name: "New group")
                    groups.append(group)
                    justAdded = group.id
                    sync()
                } label: {
                    Label("Add group", systemImage: "folder.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Text("Click a name to edit it. Accounts on an SSH host are read there: the usage API is called on the host, so its login never leaves it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { groups = settings.usageGroups }
    }

    private func sync() {
        // A new account is kept once saved (its empty host marks it as never saved).
        let saved = groups.map { group in
            var group = group
            group.accounts.removeAll { $0.host == "" }
            return group
        }
        settings.usageGroups = saved
        usage.groups = saved
        Task { await usage.refresh() }
    }
}

private struct UsageGroupHeader: View {
    @Binding var group: UsageGroup
    let startEditing: Bool
    let canRemove: Bool
    let onRemove: () -> Void
    let onCommit: () -> Void
    @State private var editing = false
    @State private var name = ""

    var body: some View {
        HStack {
            if editing {
                TextField("Group name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
            } else {
                Text(group.name)
                    .onTapGesture { name = group.name; editing = true }
                    .help("Click to rename")
            }
            Spacer()
            if canRemove {
                Button(action: onRemove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove group and its accounts")
            }
        }
        .onAppear { if startEditing { name = group.name; editing = true } }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        group.name = trimmed
        editing = false
        onCommit()
    }
}

struct UsageAccountRow: View {
    @Binding var account: UsageAccount
    let usage: SubscriptionUsage?
    let startEditing: Bool
    let onRemove: () -> Void
    let onCommit: () -> Void
    @State private var editing = false
    @State private var draft = UsageAccount(name: "", kind: .claude)
    @State private var onHost = false
    /// Logins found on the host for the draft's kind; nil until searched.
    @State private var logins: [RemoteAccountUsage.Login]?
    @State private var searching = false
    @State private var searchError: String?
    /// The user picked "Other folder…" instead of a found login.
    @State private var otherFolder = false
    private static let otherTag = "\u{0}other"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if editing {
                    TextField("Name", text: $draft.name, prompt: Text("e.g. Claude · Client A"))
                        .onSubmit(commit)
                        .onExitCommand(perform: cancel)
                } else {
                    Text(account.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginEditing)
                        .help("Click to edit")
                }
                Spacer()
                Toggle("Shown", isOn: Binding(
                    get: { account.enabled },
                    set: { account.enabled = $0; onCommit() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                Button(action: onRemove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove account")
            }

            if editing {
                editor
            } else {
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(usage?.error == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
            }
        }
        .onAppear { if startEditing { beginEditing() } }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Subscription", selection: $draft.kind) {
                ForEach(SubscriptionUsage.Kind.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: draft.kind) { old, new in
                if draft.name == old.name { draft.name = new.name }
                // Logins differ by kind: search again.
                draft.folder = nil
                findLogins()
            }
            Picker("Login on", selection: $onHost) {
                Text("This Mac").tag(false)
                Text("SSH host").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if onHost {
                HStack {
                    TextField("SSH host", text: Binding(get: { draft.host ?? "" }, set: { draft.host = $0 }),
                              prompt: Text("SSH alias, e.g. client-vps"))
                        .onSubmit(findLogins)
                        .onChange(of: draft.host) { logins = nil; searchError = nil }
                    if searching {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button("Find logins", action: findLogins)
                            .disabled(!RemoteUsage.isValidHost(trimmedHost))
                    }
                }
                if let logins, !logins.isEmpty {
                    Picker("Login", selection: loginSelection) {
                        ForEach(logins, id: \.folder) { login in
                            Text(login.detail.isEmpty ? login.folder : "\(login.folder) · \(login.detail)").tag(login.folder)
                        }
                        Divider()
                        Text("Other folder…").tag(Self.otherTag)
                    }
                }
                if logins?.isEmpty != false || otherFolder {
                    TextField("Login folder", text: Binding(get: { draft.folder ?? "" }, set: { draft.folder = $0 }),
                              prompt: Text("\(defaultFolder) (default)"))
                        .onSubmit(commit)
                }
                Text(loginHint)
                    .font(.caption2)
                    .foregroundStyle(searchError == nil ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(problem ?? "Return to save, Esc to cancel.")
                    .foregroundStyle(problem == nil ? Color.secondary : Color.orange)
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save", action: commit)
                    .disabled(problem != nil)
            }
            .font(.caption2)
            .buttonStyle(.borderless)
        }
        .font(.caption)
    }

    private var trimmedHost: String { (draft.host ?? "").trimmingCharacters(in: .whitespaces) }
    private var defaultFolder: String { draft.kind == .claude ? "~/.claude" : "~/.codex" }
    private var loginFile: String { draft.kind == .claude ? ".credentials.json" : "auth.json" }

    private var loginHint: String {
        if let searchError { return searchError }
        if searching { return "Looking for \(draft.kind.name) logins on \(trimmedHost)…" }
        guard let logins else { return "Find logins lists the \(draft.kind.name) logins on the host." }
        if logins.isEmpty { return "No \(draft.kind.name) login found. Type the folder holding \(loginFile)." }
        return otherFolder ? "Folder on the host holding \(loginFile), starting with / or ~/." : "Pick the login of this subscription."
    }

    /// The picker's value: a found login's folder, or "Other folder…".
    private var loginSelection: Binding<String> {
        Binding(
            get: { otherFolder ? Self.otherTag : (draft.folder ?? defaultFolder) },
            set: { value in
                otherFolder = value == Self.otherTag
                if !otherFolder { draft.folder = value == defaultFolder ? nil : value }
            }
        )
    }

    private func findLogins() {
        let host = trimmedHost, kind = draft.kind
        guard onHost, RemoteUsage.isValidHost(host) else { return }
        searching = true
        searchError = nil
        Task {
            // ssh blocks: off the main actor.
            let found = await Task.detached { RemoteAccountUsage.findLogins(host: host, kind: kind) }.value
            searching = false
            guard host == trimmedHost, kind == draft.kind else { return }
            logins = found.error == nil ? found.logins : nil
            searchError = found.error
            let folders = found.logins.map(\.folder)
            if let folder = draft.folder, folder != defaultFolder {
                // A typed folder the search did not see stays as typed.
                otherFolder = !folders.contains(folder) && !folders.isEmpty
            } else if !folders.contains(defaultFolder), let first = folders.first {
                draft.folder = first
                otherFolder = false
            }
        }
    }

    /// Why the draft cannot be saved, if it cannot.
    private var problem: String? {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the account a name." }
        guard onHost else { return nil }
        let host = (draft.host ?? "").trimmingCharacters(in: .whitespaces)
        if !RemoteUsage.isValidHost(host) { return "Use an alias from ~/.ssh/config or user@host." }
        let folder = (draft.folder ?? "").trimmingCharacters(in: .whitespaces)
        if !folder.isEmpty, !RemoteAccountUsage.isValidFolder(folder) { return "Folder must start with / or ~/." }
        return nil
    }

    private var statusLine: String {
        guard account.enabled else { return "Off · \(account.kind.name) · \(account.location)" }
        let place = "\(account.kind.name) · \(account.location)"
        guard let usage else { return "\(place) · Not checked yet" }
        if let error = usage.error { return error }
        let weekly = usage.weekly.map { "\(Int($0.percent.rounded()))% \($0.label)" } ?? "no weekly limit"
        return [place, usage.plan, weekly].compactMap { $0 }.joined(separator: " · ")
    }

    private func beginEditing() {
        draft = account
        onHost = account.host != nil
        logins = nil
        otherFolder = false
        editing = true
        findLogins()
    }

    private func cancel() {
        editing = false
        // A new account abandoned before its first save is not kept.
        if account.host == "" { onRemove() }
    }

    private func commit() {
        guard problem == nil else { return }
        var saved = draft
        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
        if onHost {
            saved.host = saved.host?.trimmingCharacters(in: .whitespaces)
            let folder = (saved.folder ?? "").trimmingCharacters(in: .whitespaces)
            saved.folder = folder.isEmpty || folder == defaultFolder ? nil : folder
        } else {
            saved.host = nil
            saved.folder = nil
        }
        saved.enabled = account.enabled  // the switch may have moved while the editor was open
        account = saved
        editing = false
        onCommit()
    }
}
