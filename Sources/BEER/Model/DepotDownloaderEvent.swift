import Foundation

enum DepotDownloaderEvent {
    case status(String)
    case progress(Double)
    case log(String)
    case downloadComplete
}
