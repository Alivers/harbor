import Foundation

/// A container as listed in the UI. Native rows come from `NativeParser`; Compose service rows decode
/// the Docker CLI's `--format json` field names.
public struct ContainerRow: Decodable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var image: String
    public var state: String
    public var status: String
    public var ports: String
    public init(id: String, name: String, image: String, state: String, status: String, ports: String) {
        self.id = id; self.name = name; self.image = image; self.state = state; self.status = status; self.ports = ports
    }
    enum CodingKeys: String, CodingKey { case id = "ID", name = "Names", image = "Image", state = "State", status = "Status", ports = "Ports" }
    public var running: Bool { state.lowercased() == "running" }
}
public struct ImageRow: Identifiable, Hashable, Sendable {
    /// The full reference as the CLI printed it; commands use this, never the split parts.
    public var reference: String
    public var repository: String
    public var tag: String
    public var digest: String
    public var size: String
    public var id: String { reference }
}
/// Image references as typed by users and printed by the CLI.
public enum ImageReference {
    /// One plausible argument: not empty, not an option, no whitespace.
    public static func isValid(_ text: String) -> Bool { !text.isEmpty && !text.hasPrefix("-") && !text.contains(where: \.isWhitespace) }
    /// Repository and tag, keeping registry ports (`localhost:5000/app`) and digests (`app@sha256:…`) out of the tag.
    public static func split(_ reference: String) -> (repository: String, tag: String) {
        let name = reference.firstIndex(of: "@").map { String(reference[..<$0]) } ?? reference
        let lastSlash = name.lastIndex(of: "/") ?? name.startIndex
        if let colon = name.lastIndex(of: ":"), colon > lastSlash { return (String(name[..<colon]), String(name[name.index(after: colon)...])) }
        return (name, name == reference ? "latest" : "<none>")
    }
}
public enum JSONRows {
    /// Docker prints either a JSON array or one object per line, depending on the command and version.
    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> [T] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let decoder = JSONDecoder()
        if trimmed.hasPrefix("[") { return try decoder.decode([T].self, from: Data(trimmed.utf8)) }
        return try trimmed.split(separator: "\n").map { try decoder.decode(T.self, from: Data($0.utf8)) }
    }
}
public struct ComposeProject: Codable, Identifiable, Hashable, Sendable {
    /// `compose ps` arguments whose JSON decodes into `ContainerRow`s.
    public static let serviceQuery = ["ps", "--all", "--format", "json"]
    public var id: UUID
    /// Applied in order: later files override earlier ones.
    public var files: [String]
    /// Compose resolves relative paths against the first file's directory, so this follows reordering.
    public var directory: String { URL(fileURLWithPath: files[0]).deletingLastPathComponent().path }
    public var name: String { URL(fileURLWithPath: directory).lastPathComponent }
    public init(files: [String]) {
        precondition(!files.isEmpty, "A Compose project needs at least one file")
        id = UUID(); self.files = files
    }
}
/// Compose project actions; `rawValue` is the button label.
public enum ComposeAction: String, CaseIterable, Identifiable, Sendable {
    case validate = "Validate", start = "Start", stop = "Stop", logs = "Logs", status = "Status", build = "Build"
    public var id: String { rawValue }
    public var arguments: [String] { switch self {
    case .validate: ["config", "--quiet"]
    case .start: ["up", "--detach"]
    case .stop: ["stop"]
    case .logs: ["logs", "--no-color", "--tail", "300"]
    case .status: ["ps", "--all"]
    case .build: ["build"]
    } }
    /// Validation only reads the files; everything else talks to the Docker API.
    public var needsDocker: Bool { self != .validate }
}
public struct RunOptions: Sendable {
    public var image = "nginx:alpine"
    public var name = ""
    public var ports = "127.0.0.1:8080:80"
    public var environment = ""
    public var volume = ""
    public var cpus = 2
    public var memory = "1g"
    public var extraOptions = ""
    public var command = ""
    public init() {}
    public func arguments() throws -> [String] {
        let image = image.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ImageReference.isValid(image) else { throw HarborError.message("Enter a valid image name.") }
        if !name.isEmpty && name.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]*$", options: .regularExpression) == nil { throw HarborError.message("Container names may only contain letters, digits, dots, hyphens and underscores.") }
        guard memory.range(of: "^[1-9][0-9]*[kKmMgG]?$", options: .regularExpression) != nil else { throw HarborError.message("Memory format example: 512m or 2g.") }
        var args = ["run", "--detach", "--cpus", String(cpus), "--memory", memory]
        if !name.isEmpty { args += ["--name", name] }
        // Port mappings never contain spaces or commas, so newlines, commas and spaces all separate them.
        for port in ports.split(whereSeparator: { $0 == "," || $0.isWhitespace }) { args += ["--publish", String(port)] }
        for env in environment.split(separator: "\n").map(String.init).filter({ !$0.isEmpty }) {
            guard env.contains("="), !env.hasPrefix("=") else { throw HarborError.message("Each environment variable line must be KEY=value.") }
            args += ["--env", env]
        }
        if !volume.isEmpty { args += ["--volume", volume] }
        return args + (try ArgumentTokenizer.split(extraOptions)) + [image] + (try ArgumentTokenizer.split(command))
    }
}
