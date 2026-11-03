import Foundation

/// One row of a "where should this go?" list.
struct InstallTargetOption: Identifiable, Equatable {
    let target: InstallTarget
    let availableBytes: Int64?
    /// Why the row can't be picked; nil when it can.
    let disabledReason: String?

    var id: String { target.id }
    var isEnabled: Bool { disabledReason == nil }
}
