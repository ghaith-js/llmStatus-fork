import SwiftUI

struct ServiceRowView: View {
    let provider: ServiceProvider

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
                        Text(provider.currentStatus.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let lastChecked = provider.lastChecked {
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text(lastChecked, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                Button {
                    NSWorkspace.shared.open(provider.statusURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open status page")
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
    }
}
