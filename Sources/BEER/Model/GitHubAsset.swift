import Foundation

struct GitHubAsset: Decodable {
    let name: String
    let size: Int
    let digest: String?
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case digest
        case browserDownloadURL = "browser_download_url"
    }
}
