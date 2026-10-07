import AppKit
import Foundation

extension Date {
    static var formattedLogDate: String {
        ISO8601DateFormatter().string(from: Date())
    }
}
