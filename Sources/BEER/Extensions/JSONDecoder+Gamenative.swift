import AppKit
import Foundation

extension JSONDecoder {
    static var gamenative: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
