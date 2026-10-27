import SwiftUI

/// Weekly limit gauge for one subscription, with the shorter window as a secondary figure.
struct UsageRowView: View {
    let usage: SubscriptionUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(usage.kind.name)
                    .font(.subheadline.weight(.semibold))
                if let plan = usage.plan {
                    Text(plan)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let weekly = usage.weekly {
                    Text("\(Int(weekly.percent.rounded()))% \(weekly.label)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Self.color(for: weekly.percent))
                }

                Button {
                    NSWorkspace.shared.open(usage.kind.dashboardURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Open usage page")
            }

            if let weekly = usage.weekly {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(Self.color(for: weekly.percent))
                            .frame(width: proxy.size.width * min(max(weekly.percent, 0), 100) / 100)
                    }
                }
                .frame(height: 5)
            }

            HStack(spacing: 8) {
                if let error = usage.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if let resetsAt = usage.weekly?.resetsAt {
                    Text("Resets \(Self.resetLabel(resetsAt))")
                }
                Spacer()
                if let session = usage.session {
                    Text("\(session.label): \(Int(session.percent.rounded()))%")
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    static func color(for percent: Double) -> Color {
        switch percent {
        case ..<70: .green
        case ..<90: .orange
        default: .red
        }
    }

    /// "Fri 19:00" within the week, otherwise a short date.
    static func resetLabel(_ date: Date, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(
            date.timeIntervalSince(now) < 6 * 24 * 3600 ? "EEE jj:mm" : "MMM d jj:mm"
        )
        return formatter.string(from: date)
    }
}
