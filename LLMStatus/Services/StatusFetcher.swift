import Foundation

/// Fetcher for Atlassian Statuspage API (Anthropic, OpenAI, DeepSeek, Moonshot).
enum StatusFetcher {
    static func fetchStatus(baseURL: URL) async -> StatusResponse? {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("status.json"), source: "StatusFetcher"
        ) else { return nil }
        return try? JSONDecoder().decode(StatusResponse.self, from: data)
    }

    static func fetchComponents(baseURL: URL) async -> [ServiceComponent] {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("components.json"), source: "StatusFetcher"
        ) else { return [] }
        guard let decoded = try? JSONDecoder().decode(ComponentsResponse.self, from: data) else { return [] }

        let allDTOs = decoded.components
        let groups = allDTOs.filter { $0.group == true }
        let children = allDTOs.filter { $0.group != true }

        // API-level groups (group_id set on children)
        if !groups.isEmpty {
            let childrenByGroup = Dictionary(grouping: children, by: { $0.groupId ?? "" })
            let ungrouped = children.filter { $0.groupId == nil }
            var result = groups.map { group in
                let groupChildren = (childrenByGroup[group.id] ?? []).map { $0.toServiceComponent() }
                return ServiceComponent(
                    id: group.id, name: group.name,
                    status: ServiceStatus(fromComponentStatus: group.status),
                    children: groupChildren
                )
            }
            result.append(contentsOf: ungrouped.map { $0.toServiceComponent() })
            return result
        }

        // Static grouping for providers that don't use API groups
        let flat = children.map { $0.toServiceComponent() }
        let host = baseURL.host ?? ""
        if let mapping = Self.staticGroupMapping[host] {
            return Self.applyStaticGrouping(components: flat, mapping: mapping)
        }

        return flat
    }

    // MARK: - Static grouping for providers without API groups

    /// Maps host → array of (groupName, [componentName])
    private static let staticGroupMapping: [String: [(String, Set<String>)]] = [
        "status.openai.com": [
            ("APIs", ["Batch", "File uploads", "Search", "Agent", "Codex",
                      "Chat Completions", "Realtime", "Files", "Responses",
                      "Audio", "Embeddings", "Fine-tuning", "Moderations",
                      "Compliance API"]),
            ("ChatGPT", ["Images", "Conversations", "GPTs", "Connectors/Apps",
                         "Deep Research", "ChatGPT Atlas", "Voice mode"]),
            ("Sora", ["Sora", "Image Generation", "Video generation",
                      "Video viewing", "Feed"]),
        ],
    ]

    private static func applyStaticGrouping(
        components: [ServiceComponent],
        mapping: [(String, Set<String>)]
    ) -> [ServiceComponent] {
        var used = Set<String>()
        var result: [ServiceComponent] = []

        for (groupName, memberNames) in mapping {
            let members = components.filter { memberNames.contains($0.name) }
            guard !members.isEmpty else { continue }
            members.forEach { used.insert($0.id) }

            let worstStatus = members.map(\.status).max(by: { $0.severity < $1.severity }) ?? .unknown
            result.append(ServiceComponent(
                id: groupName, name: groupName, status: worstStatus, children: members
            ))
        }

        // Append any components not in a group
        let ungrouped = components.filter { !used.contains($0.id) }

        // Deduplicate by name — keep worst status (e.g. "Login" appears 3x for OpenAI)
        var seen: [String: ServiceComponent] = [:]
        for c in ungrouped {
            if let existing = seen[c.name] {
                if c.status.severity > existing.status.severity {
                    seen[c.name] = c
                }
            } else {
                seen[c.name] = c
            }
        }

        if !seen.isEmpty {
            let others = seen.values.sorted { $0.name < $1.name }
            result.append(ServiceComponent(
                id: "other", name: "Other",
                status: others.map(\.status).max(by: { $0.severity < $1.severity }) ?? .unknown,
                children: Array(others)
            ))
        }

        return result
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("incidents/unresolved.json"), source: "StatusFetcher"
        ) else { return [] }
        guard let decoded = try? JSONDecoder().decode(IncidentsResponse.self, from: data) else { return [] }
        return decoded.incidents.compactMap { $0.toIncident() }
    }
}
