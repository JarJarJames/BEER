import Foundation

/// Valve's text KeyValues format (VDF): `"key" "value"` pairs and nested
/// `"key" { … }` blocks. Just enough to read the `installscript.vdf` files
/// Steam ships beside a game's redistributables. `#include` isn't supported,
/// and `[$WIN32]`-style conditionals are skipped rather than evaluated.
indirect enum KeyValues: Equatable {
    case value(String)
    case object([Entry])

    struct Entry: Equatable {
        let key: String
        let value: KeyValues
    }

    /// The first child named `key`, ignoring case. Steam matches keys that
    /// way, and both `InstallScript` and `installscript` occur in the wild.
    subscript(key: String) -> KeyValues? {
        children.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    var string: String? {
        if case .value(let string) = self { string } else { nil }
    }

    var children: [Entry] {
        if case .object(let entries) = self { entries } else { [] }
    }

    /// The whole document as one object. Malformed input stops the parse
    /// where it breaks; everything read up to that point is kept.
    static func parse(_ text: String) -> KeyValues {
        var tokens = Tokenizer(text)
        return .object(entries(from: &tokens))
    }

    private static func entries(from tokens: inout Tokenizer) -> [Entry] {
        var entries: [Entry] = []
        while case .string(let key)? = tokens.next() {
            switch tokens.next() {
            case .string(let value): entries.append(Entry(key: key, value: .value(value)))
            case .open: entries.append(Entry(key: key, value: .object(Self.entries(from: &tokens))))
            case .close, nil: return entries
            }
        }
        return entries
    }

    private enum Token: Equatable {
        case string(String)
        case open
        case close
    }

    private struct Tokenizer {
        private let scalars: [Unicode.Scalar]
        private var index = 0

        init(_ text: String) { scalars = Array(text.unicodeScalars) }

        mutating func next() -> Token? {
            while index < scalars.count {
                let scalar = scalars[index]
                switch scalar {
                case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                    index += 1
                case "/" where peek(1) == "/":
                    skip(past: "\n")
                case "[":
                    skip(past: "]")
                case "{":
                    index += 1
                    return .open
                case "}":
                    index += 1
                    return .close
                case "\"":
                    index += 1
                    return .string(quoted())
                default:
                    return .string(bare())
                }
            }
            return nil
        }

        private func peek(_ offset: Int) -> Unicode.Scalar? {
            index + offset < scalars.count ? scalars[index + offset] : nil
        }

        private mutating func skip(past terminator: Unicode.Scalar) {
            while index < scalars.count, scalars[index] != terminator { index += 1 }
            index += 1
        }

        private mutating func quoted() -> String {
            var result = String.UnicodeScalarView()
            while index < scalars.count, scalars[index] != "\"" {
                if scalars[index] == "\\", let escaped = peek(1) {
                    switch escaped {
                    case "\\", "\"": result.append(escaped)
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    default: result.append(contentsOf: ["\\", escaped])
                    }
                    index += 2
                } else {
                    result.append(scalars[index])
                    index += 1
                }
            }
            index += 1
            return String(result)
        }

        private mutating func bare() -> String {
            var result = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                if CharacterSet.whitespacesAndNewlines.contains(scalar) || "{}\"".unicodeScalars.contains(scalar) { break }
                result.append(scalar)
                index += 1
            }
            return String(result)
        }
    }
}
