import Foundation

/// A published port; `url` is where a browser on this Mac reaches it.
public struct PortMapping: Hashable, Sendable {
    public var hostAddress: String
    public var hostPort: Int
    public var containerPort: Int
    public var transport: String
    public init(hostAddress: String = "", hostPort: Int, containerPort: Int, transport: String = "tcp") {
        self.hostAddress = hostAddress; self.hostPort = hostPort; self.containerPort = containerPort; self.transport = transport.lowercased()
    }
    public var label: String { "\(hostPort) → \(containerPort)" + (transport == "tcp" ? "" : "/" + transport) }
    public var url: URL? {
        guard transport == "tcp" else { return nil }
        let host = ["", "0.0.0.0", "::", "[::]"].contains(hostAddress) ? "localhost" : hostAddress.contains(":") && !hostAddress.hasPrefix("[") ? "[\(hostAddress)]" : hostAddress
        return URL(string: "http://\(host):\(hostPort)")
    }
}

/// A container as listed in the UI. Native rows come from `NativeParser`; Compose service rows decode
/// the Docker CLI's `--format json` field names.
public struct ContainerRow: Decodable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var image: String
    public var state: String
    public var status: String
    public var ports: String
    public var portMappings: [PortMapping]
    public init(id: String, name: String, image: String, state: String, status: String, ports: String, portMappings: [PortMapping] = []) {
        self.id = id; self.name = name; self.image = image; self.state = state; self.status = status; self.ports = ports; self.portMappings = portMappings
    }
    enum CodingKeys: String, CodingKey { case id = "ID", name = "Names", image = "Image", state = "State", status = "Status", ports = "Ports", publishers = "Publishers" }
    private struct Publisher: Decodable {
        var address: String?; var target: Int; var published: Int; var transport: String?
        enum CodingKeys: String, CodingKey { case address = "URL", target = "TargetPort", published = "PublishedPort", transport = "Protocol" }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        image = try c.decode(String.self, forKey: .image); state = try c.decode(String.self, forKey: .state)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""; ports = try c.decodeIfPresent(String.self, forKey: .ports) ?? ""
        // Compose lists unpublished ports with PublishedPort 0, and IPv4/IPv6 bindings of one port separately.
        var seen = Set<String>()
        portMappings = (try c.decodeIfPresent([Publisher].self, forKey: .publishers) ?? []).filter { $0.published > 0 && seen.insert("\($0.published)/\($0.transport ?? "tcp")").inserted }
            .map { PortMapping(hostAddress: $0.address ?? "", hostPort: $0.published, containerPort: $0.target, transport: $0.transport ?? "tcp") }
    }
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
/// The Run Container form. List fields hold one entry each; blank entries are ignored.
public struct RunOptions: Equatable, Sendable {
    public var image: String
    public var name = ""
    public var ports: [String] = []
    public var environment: [String] = []
    public var volumes: [String] = []
    public var cpus = 2
    public var memory = "1g"
    public var extraOptions = ""
    public var command = ""
    public init(image: String = "") { self.image = image }
    /// The first thing that keeps the form from running, phrased for the user; nil when it is ready.
    public var problem: String? {
        if !ImageReference.isValid(trimmedImage) { return "Enter an image, for example nginx:alpine." }
        if !name.isEmpty && !matches(name, "^[a-zA-Z0-9][a-zA-Z0-9_.-]*$") { return "Names may only contain letters, digits, dots, hyphens and underscores." }
        if let port = Self.entries(ports).first(where: { !matches($0, "^(\\S+:)?[0-9]{1,5}:[0-9]{1,5}(/(tcp|udp))?$") }) { return "“\(port)” is not a port mapping like 8080:80 or 127.0.0.1:8080:80." }
        if Self.entries(environment).contains(where: { !matches($0, "^[^=\\s]+=") }) { return "Environment variables are written KEY=value." }
        if Self.entries(volumes).contains(where: { !$0.contains(":") }) { return "Volumes are written /host/path:/container/path or name:/path." }
        if !matches(memory, "^[1-9][0-9]*[kKmMgG]?$") { return "Memory is written like 512m or 2g." }
        if (try? ArgumentTokenizer.split(extraOptions)) == nil || (try? ArgumentTokenizer.split(command)) == nil { return "A quote in the extra arguments or command is not closed." }
        return nil
    }
    public func arguments() throws -> [String] {
        if let problem { throw HarborError.message(problem) }
        var args = ["run", "--detach", "--cpus", String(cpus), "--memory", memory]
        if !name.isEmpty { args += ["--name", name] }
        for port in Self.entries(ports) { args += ["--publish", port] }
        for env in Self.entries(environment) { args += ["--env", env] }
        for volume in Self.entries(volumes) { args += ["--volume", volume] }
        return args + (try ArgumentTokenizer.split(extraOptions)) + [trimmedImage] + (try ArgumentTokenizer.split(command))
    }
    private var trimmedImage: String { image.trimmingCharacters(in: .whitespacesAndNewlines) }
    // Values are passed literally, so only surrounding whitespace is dropped (inner spaces in KEY=value survive).
    private static func entries(_ values: [String]) -> [String] { values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
}

/// A column-aligned CLI table (`NAME    STATE    SUBNET`), split at the header's column starts.
public struct TextTable: Equatable, Sendable {
    public var columns: [String]
    public var rows: [[String]]
    /// nil when the text is not an aligned table with an upper-case header; callers then show it verbatim.
    public static func parse(_ text: String) -> TextTable? {
        let lines = text.split(whereSeparator: \.isNewline).map { Array($0) }.filter { !$0.allSatisfy(\.isWhitespace) }
        guard let header = lines.first, String(header) == String(header).uppercased(), header.contains(where: \.isLetter) else { return nil }
        // A column starts at the first character, and wherever text follows two or more spaces.
        let starts = header.indices.filter { i in header[i] != " " && (i == 0 || (i >= 2 && header[i - 1] == " " && header[i - 2] == " ")) }
        func cells(_ line: [Character]) -> [String]? {
            var result: [String] = []
            for (k, start) in starts.enumerated() {
                if k > 0, start < line.count, line[start - 1] != " " { return nil }
                let end = min(k + 1 < starts.count ? starts[k + 1] : line.count, line.count)
                result.append(start < end ? String(line[start..<end]).trimmingCharacters(in: .whitespaces) : "")
            }
            return result
        }
        guard let columns = cells(header) else { return nil }
        var rows: [[String]] = []
        for line in lines.dropFirst() { guard let row = cells(line) else { return nil }; rows.append(row) }
        return TextTable(columns: columns, rows: rows)
    }
}

public enum JSONText {
    /// Indented, key-sorted JSON for reading; the input unchanged when it is not JSON.
    public static func pretty(_ text: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return text }
        return String(decoding: data, as: UTF8.self)
    }
}
