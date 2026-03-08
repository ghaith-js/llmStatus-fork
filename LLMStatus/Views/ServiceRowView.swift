import SwiftUI

struct ServiceRowView: View {
    let provider: ServiceProvider
    @State private var isExpanded = false

    private var hasComponents: Bool { !provider.components.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: provider.currentStatus.sfSymbol)
                    .foregroundStyle(provider.currentStatus.color)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text(provider.statusDetail ?? provider.currentStatus.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if provider.statusDetail != nil {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }

                Spacer()

                if hasComponents {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }

                Button {
                    NSWorkspace.shared.open(provider.statusURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Open status page")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasComponents else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            // Components (collapsible, grouped)
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(provider.components) { component in
                        if component.isGroup {
                            // Group header
                            Text(component.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.top, 4)

                            // Group children
                            ForEach(component.children) { child in
                                componentRow(child)
                            }
                        } else {
                            componentRow(component)
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 2)
            }

            // Active incidents
            ForEach(provider.incidents.filter(\.isActive)) { incident in
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    Text(incident.name)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    if let link = incident.shortlink, let url = URL(string: link) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
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
