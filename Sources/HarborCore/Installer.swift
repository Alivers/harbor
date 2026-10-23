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

/// Apple Container versions as the CLI and the GitHub releases spell them.
public enum ReleaseVersion {
    /// The version in `container --version`: `container CLI version 1.6.0 (build: release, commit: 1a2b3c4)`.
    public static func cli(_ text: String) -> String? {
        guard let range = text.range(of: #"version v?[0-9]+(\.[0-9]+)*"#, options: .regularExpression) else { return nil }
        let version = text[range].dropFirst("version ".count)
        return String(version.hasPrefix("v") ? version.dropFirst() : version)
    }
    /// Whether `candidate` is a later release than `installed`, comparing numbers (1.10.0 is later than 1.9.2).
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        func parts(_ version: String) -> [Int] { version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }
        let a = parts(candidate), b = parts(installed), count = max(a.count, b.count)
        func padded(_ v: [Int]) -> [Int] { v + Array(repeating: 0, count: count - v.count) }
        return padded(b).lexicographicallyPrecedes(padded(a))
    }
    /// Whether the CLI at `path` belongs to Homebrew (a link into its Cellar), which then also updates it.
    public static func managedByHomebrew(_ path: String) -> Bool {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path.contains("/Cellar/")
    }
    /// The release page of a version, for its notes.
    public static func notes(_ version: String) -> URL { InstallerPackage.releasesPage.appendingPathComponent("tag").appendingPathComponent(version) }
}
