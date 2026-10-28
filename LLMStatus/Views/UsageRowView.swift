import SwiftUI

/// Weekly limit gauge for one subscription, with the shorter window as a secondary figure.
struct UsageRowView: View {
    let usage: SubscriptionUsage
    @State private var isExpanded: Bool

    init(usage: SubscriptionUsage, startExpanded: Bool = false) {
        self.usage = usage
        _isExpanded = State(initialValue: startExpanded)
    }

    private var hasBreakdown: Bool { !usage.breakdown.isEmpty && usage.weekly != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(usage.displayName)
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

                if hasBreakdown {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
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
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasBreakdown else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
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
                    Label(Self.errorLine(error, keptFrom: usage.weekly == nil ? nil : usage.fetchedAt), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if let resetsAt = usage.weekly?.resetsAt {
                    Text("Resets \(Self.resetLabel(resetsAt))")
                }
                Spacer()
                if let session = usage.session {
                    // The short window resets within hours: a countdown, kept current.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.sessionLabel(session, now: context.date))
                            .monospacedDigit()
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if isExpanded, let weekly = usage.weekly {
                breakdown(weeklyPercent: weekly.percent)
            }
        }
    }

    /// Apps (or SSH hosts, then their apps), then projects, each with its estimated part of the weekly percentage.
    private func breakdown(weeklyPercent: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(usage.breakdown) { top in
                shareRow(top.name, share: top.share, weeklyPercent: weeklyPercent)
                    .font(.caption.weight(.medium))
                ForEach(top.children) { child in
                    shareRow(child.name, share: child.share, weeklyPercent: weeklyPercent)
                        .font(child.children.isEmpty ? .caption2 : .caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                    ForEach(child.children) { project in
                        shareRow(project.name, share: project.share, weeklyPercent: weeklyPercent)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 24)
                    }
                }
            }
            ForEach(usage.breakdownErrors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text("Estimated from logs (tokens). \(usage.kind.breakdownCaveat)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private func shareRow(_ name: String, share: Double, weeklyPercent: Double) -> some View {
        HStack {
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(Self.percentLabel(share * weeklyPercent))
                .monospacedDigit()
            Text(share < 0.005 ? "(<1%)" : "(\(Int((share * 100).rounded()))%)")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    /// One decimal below 10 % so small consumers are not all "0%"; "<0.1%" rather than a false zero.
    static func percentLabel(_ value: Double) -> String {
        switch value {
        case ..<0.05: "<0.1%"
        case ..<10: String(format: "%.1f%%", value)
        default: "\(Int(value.rounded()))%"
        }
    }

    /// The error, and when the limits still shown were read.
    static func errorLine(_ error: String, keptFrom date: Date?) -> String {
        guard let date else { return error }
        return "\(error) · as of \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// "5h: 5% · resets in 3h 45m". An unused window has no reset time yet: its clock starts
    /// with the next message. No countdown once the reset time has passed.
    static func sessionLabel(_ window: SubscriptionUsage.Window, now: Date = Date()) -> String {
        let used = "\(window.label): \(Int(window.percent.rounded()))%"
        guard let resetsAt = window.resetsAt else { return window.percent == 0 ? "\(used) · starts on next use" : used }
        guard let left = MenuBarContent.countdown(window, now: now), resetsAt > now else { return used }
        return "\(used) · resets in \(left)"
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
