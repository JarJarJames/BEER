import Foundation

enum RosettaInstallError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let detail): RosettaStrings.installFailed(detail)
        }
    }
}
