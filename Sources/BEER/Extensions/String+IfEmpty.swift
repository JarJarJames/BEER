import Foundation

extension String {
    func ifEmpty(default value: String) -> String { isEmpty ? value : self }
}
