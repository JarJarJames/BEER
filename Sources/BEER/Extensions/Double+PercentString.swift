import Foundation

extension Double {
    /// A 0...1 fraction as a whole-number percentage, e.g. `0.42` -> "42%".
    var percentString: String { String(format: "%.0f%%", self * 100) }
}
