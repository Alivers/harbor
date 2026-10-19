import Foundation

public struct ContainerRow: Decodable, Identifiable, Sendable {
    public var identifier: String
    public var Names: String
    public var Image: String
    public var State: String
    public var Status: String
    public var Ports: String
    public var id: String { identifier }
    enum CodingKeys: String, CodingKey { case identifier = "ID", Names, Image, State, Status, Ports }
    public var running: Bool { State.lowercased() == "running" }
}
public struct ImageRow: Decodable, Identifiable, Sendable {
    public var identifier: String
    public var Repository: String
    public var Tag: String
    public var Size: String
    public var id: String { identifier + Repository + Tag }
    enum CodingKeys: String, CodingKey { case identifier = "ID", Repository, Tag, Size }
    public var reference: String { Repository == "<none>" ? identifier : Repository + ":" + Tag }
}
public enum JSONRows {
    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> [T] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let decoder = JSONDecoder()
        if trimmed.hasPrefix("[") { return try decoder.decode([T].self, from: Data(trimmed.utf8)) }
        return try trimmed.split(separator: "\n").map { try decoder.decode(T.self, from: Data($0.utf8)) }
    }
}
public struct ComposeProject: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var files: [String]
    public var directory: String
    public var name: String { URL(fileURLWithPath: directory).lastPathComponent }
    public init(files: [String]) {
        id = UUID(); self.files = files
        directory = URL(fileURLWithPath: files[0]).deletingLastPathComponent().path
    }
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
        guard !image.isEmpty, !image.hasPrefix("-"), !image.contains(where: { $0.isWhitespace }) else { throw HarborError.message("Enter a valid image name.") }
        if !name.isEmpty && name.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]*$", options: .regularExpression) == nil { throw HarborError.message("Container names may only contain letters, digits, dots, hyphens and underscores.") }
        guard memory.range(of: "^[1-9][0-9]*[kKmMgG]?$", options: .regularExpression) != nil else { throw HarborError.message("Memory format example: 512m or 2g.") }
        var args = ["run", "--detach", "--cpus", String(cpus), "--memory", memory]
        if !name.isEmpty { args += ["--name", name] }
        for port in ports.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) { args += ["--publish", port] }
        for env in environment.split(separator: "\n").map(String.init).filter({ !$0.isEmpty }) {
            guard env.contains("="), !env.hasPrefix("=") else { throw HarborError.message("Each environment variable line must be KEY=value.") }
            args += ["--env", env]
        }
        if !volume.isEmpty { args += ["--volume", volume] }
        return args + (try ArgumentTokenizer.split(extraOptions)) + [image] + (try ArgumentTokenizer.split(command))
    }
}
