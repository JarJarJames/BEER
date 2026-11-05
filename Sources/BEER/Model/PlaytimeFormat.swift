import Foundation

/// How play time is written, on the game page and in the library's caption.
enum PlaytimeFormat: String, CaseIterable, Identifiable {
    /// Steam's own style, e.g. "43.4 hours": the original look.
    case decimalHours
    /// e.g. "43h 24m".
    case hoursAndMinutes
    /// e.g. "43 hours".
    case wholeHours

    var id: String { rawValue }

    var label: String {
        switch self {
        case .decimalHours: "43.4 hours"
        case .hoursAndMinutes: "43h 24m"
        case .wholeHours: "43 hours"
        }
    }

    func text(minutes: Int) -> String {
        if self == .hoursAndMinutes {
            let hours = minutes / 60, rest = minutes % 60
            if hours == 0 { return "\(rest)m" }
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        if self == .decimalHours { return String(format: "%.1f hours", Double(minutes) / 60) }
        let hours = Int((Double(minutes) / 60).rounded())
        return "\(hours) hour\(hours == 1 ? "" : "s")"
    }
}
