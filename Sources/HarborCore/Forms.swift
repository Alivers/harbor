import Foundation

/// Names the CLI accepts for containers, networks and volumes.
public enum ResourceName {
    public static func isValid(_ name: String) -> Bool { name.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]*$", options: .regularExpression) != nil }
}

/// The Build Image form → `container build`. Paths are absolute, so nothing depends on a working directory.
public struct BuildOptions: Equatable, Sendable {
    /// The build context folder.
    public var context: String
    /// Optional; the CLI looks for Dockerfile, then Containerfile, in the context.
    public var dockerfile = ""
    public var tags: [String] = []
    public var buildArgs: [String] = []
    public var target = ""
    /// Empty, `linux/arm64` or `linux/amd64`.
    public var platform = ""
    public var noCache = false
    public var pull = false
    public init(context: String = "", dockerfile: String = "") { self.context = context; self.dockerfile = dockerfile }
    public static let platforms = ["", "linux/arm64", "linux/amd64"]
    /// A dropped Dockerfile builds with its folder as the context; a dropped folder is the context itself.
    public init(dropped path: String) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue { self.init(context: path) }
        else { self.init(context: URL(fileURLWithPath: path).deletingLastPathComponent().path, dockerfile: path) }
    }
    public var problem: String? {
        if !Self.isFolder(context) { return "Choose the build context folder." }
        if !dockerfile.isEmpty && !(dockerfile.hasPrefix("/") && FileManager.default.fileExists(atPath: dockerfile)) { return "The Dockerfile must be an existing file." }
        let tags = Self.entries(tags)
        if tags.isEmpty { return "Add a tag, for example local/app:dev, so you can find the image afterwards." }
        if let tag = tags.first(where: { !ImageReference.isValid($0) }) { return "“\(tag)” is not an image name." }
        if Self.entries(buildArgs).contains(where: { $0.range(of: "^[^=\\s]+=", options: .regularExpression) == nil }) { return "Build arguments are written KEY=value." }
        if !target.isEmpty && !ResourceName.isValid(target) { return "The target is a stage name from the Dockerfile." }
        if !Self.platforms.contains(platform) { return "Platform is linux/arm64 or linux/amd64." }
        return nil
    }
    public func arguments() throws -> [String] {
        if let problem { throw HarborError.message(problem) }
        // Plain progress is line-based, so the activity output stays readable without a terminal.
        var args = ["build", "--progress", "plain"]
        for tag in Self.entries(tags) { args += ["--tag", tag] }
        if !dockerfile.isEmpty { args += ["--file", dockerfile] }
        for arg in Self.entries(buildArgs) { args += ["--build-arg", arg] }
        if !target.isEmpty { args += ["--target", target] }
        if !platform.isEmpty { args += ["--platform", platform] }
        if noCache { args.append("--no-cache") }
        if pull { args.append("--pull") }
        return args + [context]
    }
    static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return path.hasPrefix("/") && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    public static func entries(_ values: [String]) -> [String] { values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

/// The Create Network form → `container network create`.
public struct NetworkOptions: Equatable, Sendable {
    public var name = ""
    /// Optional IPv4 CIDR such as 192.168.100.0/24.
    public var subnet = ""
    /// Host-only: containers can reach each other and the Mac, but not the internet.
    public var hostOnly = false
    public var labels: [String] = []
    public init() {}
    public var problem: String? {
        if !ResourceName.isValid(name) { return "Names may only contain letters, digits, dots, hyphens and underscores." }
        if !subnet.isEmpty && subnet.range(of: #"^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$"#, options: .regularExpression) == nil { return "The subnet is written in CIDR form, like 192.168.100.0/24." }
        if BuildOptions.entries(labels).contains(where: { $0.range(of: "^[^=\\s]+=", options: .regularExpression) == nil }) { return "Labels are written key=value." }
        return nil
    }
    public func arguments() throws -> [String] {
        if let problem { throw HarborError.message(problem) }
        var args = ["network", "create"]
        if hostOnly { args.append("--internal") }
        if !subnet.isEmpty { args += ["--subnet", subnet] }
        for label in BuildOptions.entries(labels) { args += ["--label", label] }
        return args + [name]
    }
}

/// The Create Volume form → `container volume create`.
public struct VolumeOptions: Equatable, Sendable {
    public var name = ""
    /// Optional size such as 10g; the CLI picks a default when empty.
    public var size = ""
    public var labels: [String] = []
    public init() {}
    public var problem: String? {
        if !ResourceName.isValid(name) { return "Names may only contain letters, digits, dots, hyphens and underscores." }
        if !size.isEmpty && size.range(of: "^[1-9][0-9]*[kKmMgGtTpP]?$", options: .regularExpression) == nil { return "The size is written like 512m or 10g." }
        if BuildOptions.entries(labels).contains(where: { $0.range(of: "^[^=\\s]+=", options: .regularExpression) == nil }) { return "Labels are written key=value." }
        return nil
    }
    public func arguments() throws -> [String] {
        if let problem { throw HarborError.message(problem) }
        var args = ["volume", "create"]
        if !size.isEmpty { args += ["-s", size] }
        for label in BuildOptions.entries(labels) { args += ["--label", label] }
        return args + [name]
    }
}
