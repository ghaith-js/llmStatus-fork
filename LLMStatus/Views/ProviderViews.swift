import SwiftUI

extension ServiceProvider {
    /// What is affected, most specific first: components not operational, then the components
    /// named by active incidents, then the incidents themselves.
    /// Each item carries its own status when the component is known, else the provider's.
    var impacted: [(name: String, status: ServiceStatus)] {
        var seen = Set<String>()
        let leaves = components.flatMap { $0.isGroup ? $0.children : [$0] }
        let degraded = leaves.filter { $0.status != .operational && $0.status != .unknown }
        if !degraded.isEmpty {
            return degraded.filter { seen.insert($0.name).inserted }.map { ($0.name, $0.status) }
        }
        let active = incidents.filter(\.isActive)
        let named = active.flatMap(\.affectedComponents)
        return (named.isEmpty ? active.map(\.name) : named)
            .filter { seen.insert($0).inserted }
            .map { ($0, currentStatus) }
    }
}

/// One provider in the two-column status gallery. Tapping it opens `ProviderDetailView`.
struct ProviderCardView: View {
    let provider: ServiceProvider
    /// Impacted items shown before "+N more".
    static let maxImpacted = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(provider.shortName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Image(systemName: provider.currentStatus.sfSymbol)
                    .foregroundStyle(provider.currentStatus.color)
                    .font(.subheadline)
            }

            detail
                .font(.caption2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6)))
        .overlay {
            if provider.currentStatus.severity >= 2 {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(provider.currentStatus.color.opacity(0.6), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .help(provider.name)
    }

    @ViewBuilder
    private var detail: some View {
        let impacted = provider.impacted
        if let loading = provider.statusDetail {
            HStack(spacing: 4) {
                Text(loading).foregroundStyle(.secondary).lineLimit(1)
                ProgressView().controlSize(.mini)
            }
        } else if provider.currentStatus == .operational || impacted.isEmpty {
            Text(provider.currentStatus.label)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(impacted.prefix(Self.maxImpacted), id: \.name) { item in
                    Text(item.name)
                        .foregroundStyle(item.status.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if impacted.count > Self.maxImpacted {
                    Text("+\(impacted.count - Self.maxImpacted) more")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Components and active incidents of one provider, shown in place of the gallery.
struct ProviderDetailView: View {
    let provider: ServiceProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: provider.currentStatus.sfSymbol)
                    .foregroundStyle(provider.currentStatus.color)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.headline)
                    Text(provider.statusDetail ?? provider.currentStatus.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(provider.statusURL)
                } label: {
                    Label("Status page", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focusable(false)
            }

            // Active incidents
            ForEach(provider.incidents.filter(\.isActive)) { incident in
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(incident.name)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    if let link = incident.shortlink, let url = URL(string: link) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                        }
                    }
                }
            }

            // Components (grouped)
            if !provider.components.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(provider.components) { component in
                        if component.isGroup {
                            Text(component.name)
                                .font(.caption.weight(.semibold))
                                .padding(.top, 4)
                            ForEach(component.children) { child in
                                componentRow(child)
                            }
                        } else {
                            componentRow(component)
                        }
                    }
                }
            }
        }
        .focusEffectDisabled()
    }

    private func componentRow(_ component: ServiceComponent) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(component.status.color)
                .frame(width: 6, height: 6)
            Text(component.name)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(component.status.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
