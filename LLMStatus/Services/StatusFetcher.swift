import Foundation

/// Fetcher for Atlassian Statuspage API (Anthropic, OpenAI, Cursor, DeepSeek, Moonshot).
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
    /// Components with the same name (e.g. "Login") can appear in multiple groups.
    private static let staticGroupMapping: [String: [(String, Set<String>)]] = [
        "status.openai.com": [
            ("APIs", ["Chat Completions", "Responses", "Fine-tuning", "Embeddings",
                      "Images", "Batch", "Audio", "Moderations", "Realtime",
                      "Files", "Login", "Sora"]),
            ("ChatGPT", ["Conversations", "Login", "Compliance API", "Search",
                         "File uploads", "Voice mode", "GPTs", "Image Generation",
                         "Deep Research", "Agent", "Codex", "ChatGPT Atlas",
                         "Connectors/Apps"]),
            ("Sora", ["Login", "Video generation", "Video viewing", "Feed",
                      "Image Generation"]),
        ],
    ]

    private static func applyStaticGrouping(
        components: [ServiceComponent],
        mapping: [(String, Set<String>)]
    ) -> [ServiceComponent] {
        // Build a lookup: name → [components] (handles duplicate names like "Login")
        var byName: [String: [ServiceComponent]] = [:]
        for c in components {
            byName[c.name, default: []].append(c)
        }

        var usedIDs = Set<String>()
        var result: [ServiceComponent] = []

        for (groupName, memberNames) in mapping {
            var members: [ServiceComponent] = []
            for name in memberNames {
                guard let candidates = byName[name] else { continue }
                // Pick the first unused candidate, or the first one if all used
                if let unused = candidates.first(where: { !usedIDs.contains($0.id) }) {
                    members.append(unused)
                    usedIDs.insert(unused.id)
                } else if let fallback = candidates.first {
                    // Duplicate name across groups (e.g. "Login") — create a copy with group-scoped ID
                    members.append(ServiceComponent(
                        id: "\(groupName)-\(fallback.id)", name: fallback.name,
                        status: fallback.status, children: fallback.children
                    ))
                }
            }
            guard !members.isEmpty else { continue }

            let worstStatus = members.map(\.status).max(by: { $0.severity < $1.severity }) ?? .unknown
            result.append(ServiceComponent(
                id: groupName, name: groupName, status: worstStatus, children: members
            ))
        }

        // Append any components not claimed by any group
        let ungrouped = components.filter { !usedIDs.contains($0.id) }
        if !ungrouped.isEmpty {
            let others = ungrouped.sorted { $0.name < $1.name }
            result.append(ServiceComponent(
                id: "other", name: "Other",
                status: others.map(\.status).max(by: { $0.severity < $1.severity }) ?? .unknown,
                children: others
            ))
        }

        return result
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("incidents.json"), source: "StatusFetcher"
        ) else { return [] }
        guard let decoded = try? JSONDecoder().decode(IncidentsResponse.self, from: data) else { return [] }
        return decoded.incidents.compactMap { $0.toIncident() }.filter { $0.resolvedAt == nil }
    }
}
