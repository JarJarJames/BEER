import Foundation

/// How the last-played date is written, on the game page and in the
/// library's caption.
enum LastPlayedFormat: String, CaseIterable, Identifiable {
    /// "Today", "Yesterday", "3 days ago", then the date after a week.
    case relative
    /// The date, e.g. "Oct 22, 2026".
    case date

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relative: "Today, 3 days ago"
        case .date: "Oct 22, 2026"
        }
    }

    func text(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let dateText = date.formatted(date: .abbreviated, time: .omitted)
        guard self == .relative else { return dateText }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days) days ago"
        default: return dateText
        }
    }
}
