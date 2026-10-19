import Foundation

/// Browsing a running container's files with the container's own `ls`, and copying with `container copy`.
public enum ContainerFiles {
    public struct Entry: Identifiable, Hashable, Sendable {
        public var name: String
        public var isDirectory: Bool
        public var id: String { name }
        public init(name: String, isDirectory: Bool) { self.name = name; self.isDirectory = isDirectory }
    }
    /// `ls -1Ap` prints one name per line, hidden files included, with a slash after directories;
    /// BusyBox and GNU coreutils agree on it. The path is absolute, so it can never read as an option.
    public static func listArguments(container: String, path: String) -> [String] { ["exec", container, "ls", "-1Ap", path] }
    /// Folders first, then files, each in Finder order.
    public static func parse(_ output: String) -> [Entry] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> Entry? in
            let name = String(line)
            if name == "./" || name == "../" { return nil }
            return name.hasSuffix("/") ? Entry(name: String(name.dropLast()), isDirectory: true) : Entry(name: name, isDirectory: false)
        }
        .sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    /// An absolute path with single slashes and no trailing slash; nil for a relative path.
    public static func normalize(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/"), !trimmed.contains(where: \.isNewline) else { return nil }
        var parts: [Substring] = []
        for part in trimmed.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }
    public static func join(_ directory: String, _ name: String) -> String { directory == "/" ? "/" + name : directory + "/" + name }
    public static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), path != "/" else { return "/" }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }
    /// `container copy` tells the sides apart by `id:path`, so a local path with a colon would be misread.
    public static func localPathProblem(_ path: String) -> String? {
        path.contains(":") ? "Local paths with a colon cannot be copied; rename the file or folder first." : nil
    }
    public static func downloadArguments(container: String, path: String, to localFolder: String) throws -> [String] {
        if let problem = localPathProblem(localFolder) { throw HarborError.message(problem) }
        return ["copy", container + ":" + path, localFolder]
    }
    public static func uploadArguments(_ localPath: String, container: String, folder: String) throws -> [String] {
        if let problem = localPathProblem(localPath) { throw HarborError.message(problem) }
        return ["copy", localPath, container + ":" + (folder.hasSuffix("/") ? folder : folder + "/")]
    }
}

/// Copying images from another Docker engine (OrbStack, Docker Desktop, Colima) into Apple Container:
/// `docker image save` against that engine's socket, then `container image load`.
/// The source is always named by its socket, like every other Docker command Harbor runs.
public enum DockerImport {
    public struct Source: Identifiable, Hashable, Sendable {
        public var name: String
        public var socket: String
        public var id: String { socket }
        public init(name: String, socket: String) { self.name = name; self.socket = socket }
    }
    /// Engines that keep their socket in a well-known place, in the order they are offered.
    public static func candidates(home: String = NSHomeDirectory()) -> [Source] {
        [Source(name: "OrbStack", socket: home + "/.orbstack/run/docker.sock"),
         Source(name: "Docker Desktop", socket: home + "/.docker/run/docker.sock"),
         Source(name: "Colima", socket: home + "/.colima/default/docker.sock"),
         Source(name: "Rancher Desktop", socket: home + "/.rd/docker.sock"),
         Source(name: "System Docker", socket: "/var/run/docker.sock")]
    }
    /// Candidates whose socket exists right now.
    public static func availableSources(home: String = NSHomeDirectory()) -> [Source] {
        candidates(home: home).filter { FileManager.default.fileExists(atPath: $0.socket) }
    }
    /// A row of `docker image ls --format json`.
    public struct Image: Decodable, Identifiable, Hashable, Sendable {
        public var repository: String
        public var tag: String
        public var imageID: String
        public var size: String
        public var id: String { reference }
        /// What `docker image save` and `container image load` both understand.
        public var reference: String { repository + ":" + tag }
        enum CodingKeys: String, CodingKey { case repository = "Repository", tag = "Tag", imageID = "ID", size = "Size" }
    }
    public static let listArguments = ["image", "ls", "--format", "json"]
    /// Untagged images cannot be named in Apple Container, so they are left out.
    public static func images(_ json: String) throws -> [Image] {
        try JSONRows.decode(Image.self, from: json).filter { $0.repository != "<none>" && $0.tag != "<none>" }
    }
    public static func saveArguments(_ reference: String, to archive: String) -> [String] { ["image", "save", "--output", archive, reference] }
    public static func loadArguments(_ archive: String) -> [String] { ["image", "load", "--input", archive] }
}
