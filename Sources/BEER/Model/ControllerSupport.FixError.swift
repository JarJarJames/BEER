import Foundation

extension ControllerSupport {
    enum FixError: LocalizedError {
        case artifactsMissing
        case runtimeHidMissing

        var errorDescription: String? {
            switch self {
            case .artifactsMissing:
                return "Controller fix is not installed. Run Tools/ControllerFix/build.sh."
            case .runtimeHidMissing:
                return "This bottle's Wine runtime has no hid.dll to forward to."
            }
        }
    }
}
