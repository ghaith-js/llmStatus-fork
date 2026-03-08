import AppKit
import SwiftUI

enum ServiceStatus: String, Codable, CaseIterable {
    case operational
    case degraded
    case majorOutage
    case critical
    case unknown

    var color: Color {
        switch self {
        case .operational: .green
        case .degraded:    .yellow
        case .majorOutage: .orange
        case .critical:    .red
        case .unknown:     .gray
        }
    }

    var nsColor: NSColor {
        switch self {
        case .operational: .systemGreen
        case .degraded:    .systemYellow
        case .majorOutage: .systemOrange
        case .critical:    .systemRed
        case .unknown:     .systemGray
        }
    }

    var sfSymbol: String {
        switch self {
        case .operational: "checkmark.circle.fill"
        case .degraded:    "exclamationmark.triangle.fill"
        case .majorOutage: "xmark.circle.fill"
        case .critical:    "xmark.octagon.fill"
        case .unknown:     "questionmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .operational: "Operational"
        case .degraded:    "Degraded"
        case .majorOutage: "Major Outage"
        case .critical:    "Critical"
        case .unknown:     "Unknown"
        }
    }

    /// Maps the Statuspage API `indicator` field to our enum.
    init(fromIndicator indicator: String) {
        switch indicator {
        case "none":     self = .operational
        case "minor":    self = .degraded
        case "major":    self = .majorOutage
        case "critical": self = .critical
        default:         self = .unknown
        }
    }

    /// Severity rank for aggregation (higher = worse).
    var severity: Int {
        switch self {
        case .operational: 0
        case .unknown:     1
        case .degraded:    2
        case .majorOutage: 3
        case .critical:    4
        }
    }
}
