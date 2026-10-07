import Foundation

struct RuntimeBundleManifest: Decodable {
    let name: String?
    let version: String?
    let entrypoints: RuntimeEntrypoints
}
