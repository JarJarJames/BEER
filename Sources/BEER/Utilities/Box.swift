import Foundation

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
