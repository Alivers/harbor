import Foundation

/// The signed installer package of an apple/container GitHub release.
public struct InstallerPackage: Equatable, Sendable {
    public static let latestRelease = URL(string: "https://api.github.com/repos/apple/container/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/apple/container/releases")!
    public var version: String
    public var url: URL
    public var size: Int64
    /// Safe to use as a local file name: the last path component of an official download URL.
    public var fileName: String { url.lastPathComponent }

    /// The `.pkg` asset of a release (the signed one when there are several), accepted only when it is
    /// served over HTTPS from apple/container's own release downloads.
    public static func parse(release data: Data) -> InstallerPackage? {
        struct Asset: Decodable {
            var name: String; var url: URL; var size: Int64?
            enum CodingKeys: String, CodingKey { case name, url = "browser_download_url", size }
        }
        struct Release: Decodable {
            var tag: String; var assets: [Asset]
            enum CodingKeys: String, CodingKey { case tag = "tag_name", assets }
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { return nil }
        let official = release.assets.filter {
            $0.name.hasSuffix(".pkg") && $0.url.scheme == "https" && $0.url.host() == "github.com"
                && $0.url.path.hasPrefix("/apple/container/releases/download/")
        }
        let signed = official.first { $0.name.contains("signed") && !$0.name.contains("unsigned") }
        guard let asset = signed ?? official.first else { return nil }
        return InstallerPackage(version: release.tag, url: asset.url, size: asset.size ?? 0)
    }
}
