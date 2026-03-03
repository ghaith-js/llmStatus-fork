import SwiftUI

struct IncidentDetailView: View {
    let incident: Incident

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(incident.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if let link = incident.shortlink, let url = URL(string: link) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }

            // Badges
            HStack(spacing: 6) {
                Badge(text: incident.impact.rawValue.capitalized, color: impactColor)
                Badge(text: incident.status.rawValue.capitalized, color: .secondary)
            }

            // Timeline
            if !incident.updates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(incident.updates) { update in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(.tertiary)
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(update.status.rawValue.capitalized)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(update.body)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(update.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private var impactColor: Color {
        switch incident.impact {
        case .none: .green
        case .minor: .yellow
        case .major: .orange
        case .critical: .red
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
