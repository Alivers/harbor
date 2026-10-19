import Foundation

/// The primary backend is Apple's CLI. Docker is only used by the optional Compose section.
public enum NativeParser {
    private static func objects(_ text: String) throws -> [[String: Any]] {
        guard let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else {
            throw HarborError.message("The native CLI returned unrecognized JSON. Run diagnostics and check the version.")
        }
        return value
    }
    public static func containers(_ text: String) throws -> [ContainerRow] {
        try objects(text).map { row in
            guard let config = row["configuration"] as? [String: Any], let id = config["id"] as? String,
                  let image = config["image"] as? [String: Any], let reference = image["reference"] as? String else {
                throw HarborError.message("Container JSON is missing configuration.id / image.reference; check the raw CLI output.")
            }
            let status = row["status"] as? [String: Any]
            guard let state = (status?["state"] as? String) ?? (row["status"] as? String) else {
                throw HarborError.message("Container JSON is missing the status field.")
            }
            let networks = (status?["networks"] ?? row["networks"]) as? [[String: Any]] ?? []
            let addresses = networks.compactMap { $0["ipv4Address"] as? String }.joined(separator: ", ")
            let resources = config["resources"] as? [String: Any] ?? [:]
            let cpus = (resources["cpus"] as? NSNumber)?.stringValue ?? "?"
            let memory = (resources["memoryInBytes"] as? NSNumber)?.int64Value ?? 0
            let ports = config["publishedPorts"] as? [[String: Any]] ?? []
            let published = ports.map { port -> String in
                let host = port["hostPort"] ?? "?", target = port["containerPort"] ?? "?"
                return "\(host) → \(target)"
            }.joined(separator: ", ")
            let details = "\(cpus) CPU · \(ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory))" + (addresses.isEmpty ? "" : " · " + addresses)
            return ContainerRow(identifier: id, Names: id, Image: reference, State: state, Status: details, Ports: published)
        }
    }
    public static func images(_ text: String) throws -> [ImageRow] {
        try objects(text).map { row in
            let config = row["configuration"] as? [String: Any] ?? row
            guard let reference = (config["name"] ?? config["reference"]) as? String else {
                throw HarborError.message("Image JSON is missing a name. Check the raw CLI output.")
            }
            let descriptor = config["descriptor"] as? [String: Any] ?? [:]
            let digest = descriptor["digest"] as? String ?? reference
            let variants = row["variants"] as? [[String: Any]] ?? []
            let size = variants.reduce(Int64(0)) { $0 + (($1["size"] as? NSNumber)?.int64Value ?? 0) }
            let lastSlash = reference.lastIndex(of: "/") ?? reference.startIndex
            let colon = reference.lastIndex(of: ":")
            let tagged = colon.map { $0 > lastSlash } ?? false
            let repository = tagged ? String(reference[..<colon!]) : reference
            let tag = tagged ? String(reference[reference.index(after: colon!)...]) : "latest"
            return ImageRow(identifier: digest, Repository: repository, Tag: tag, Size: size > 0 ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file) : "—")
        }
    }
}

/// Shell-like argument splitting only: no evaluation, expansion, redirects, or pipelines.
public enum ArgumentTokenizer {
    public static func split(_ text: String) throws -> [String] {
        var tokens: [String] = [], current = "", quote: Character?, escape = false, active = false
        for c in text {
            if escape { current.append(c); escape = false; active = true; continue }
            if c == "\\", quote != "'" { escape = true; active = true; continue }
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
                active = true; continue
            }
            if c == "'" || c == "\"" { quote = c; active = true; continue }
            if c.isWhitespace { if active { tokens.append(current); current = ""; active = false }; continue }
            current.append(c); active = true
        }
        guard quote == nil, !escape else { throw HarborError.message("Unclosed quote or escape in arguments.") }
        if active { tokens.append(current) }
        return tokens
    }
}

public enum NativeHelp {
    public static func matches(_ text: String, path: [String]) -> Bool {
        if path.isEmpty { return text.contains("USAGE: container") }
        let expected = "USAGE: container " + path.joined(separator: " ")
        if text.contains(expected) { return true }
        // Plugins print their own executable name rather than the dispatcher name.
        return path.first == "k8s" && text.contains("USAGE: " + path.joined(separator: " "))
    }
}

public struct NativeOperation: Identifiable, Hashable, Sendable {
    public let group: String
    public let title: String
    public let path: [String]
    public let example: String
    public let terminal: Bool
    public let destructive: Bool
    public var id: String { path.joined(separator: " ") }
    public init(_ group: String, _ title: String, _ path: String, _ example: String = "", terminal: Bool = false, destructive: Bool = false) {
        self.group = group; self.title = title; self.path = path.split(separator: " ").map(String.init)
        self.example = example; self.terminal = terminal; self.destructive = destructive
    }
    public static let all: [NativeOperation] = [
        .init("Containers", "Run Container", "run", "--detach --name web -p 127.0.0.1:8080:80 nginx:alpine"),
        .init("Containers", "Create Without Starting", "create", "--name web nginx:alpine"),
        .init("Containers", "Start", "start", "web"), .init("Containers", "Stop", "stop", "web"),
        .init("Containers", "Send Signal", "kill", "web", destructive: true),
        .init("Containers", "Delete", "delete", "web", destructive: true),
        .init("Containers", "List", "list", "--all --format json"),
        .init("Containers", "Exec", "exec", "--interactive --tty web /bin/sh", terminal: true),
        .init("Containers", "Export Filesystem", "export", "-o /tmp/web.tar web"),
        .init("Containers", "Reclaim Filesystem Space", "clean", "web"),
        .init("Containers", "Logs", "logs", "-n 300 web"),
        .init("Containers", "Inspect", "inspect", "web"),
        .init("Containers", "Stats", "stats", "--no-stream --format json"),
        .init("Containers", "Copy Files", "copy", "./file.txt web:/tmp/file.txt"),
        .init("Containers", "Prune Stopped Containers", "prune", destructive: true),
        .init("Images", "List", "image list", "--format json"),
        .init("Images", "Pull", "image pull", "nginx:alpine"),
        .init("Images", "Push", "image push", "registry.example.com/team/app:latest"),
        .init("Images", "Save Archive", "image save", "-o /tmp/images.tar nginx:alpine"),
        .init("Images", "Load Archive", "image load", "-i /tmp/images.tar"),
        .init("Images", "Tag", "image tag", "nginx:alpine local/web:dev"),
        .init("Images", "Delete", "image delete", "local/web:dev", destructive: true),
        .init("Images", "Prune Unused Images", "image prune", destructive: true),
        .init("Images", "Inspect", "image inspect", "nginx:alpine"),
        .init("Build", "Build Image", "build", "--tag local/app:dev ."),
        .init("Build", "Start Builder", "builder start"), .init("Build", "Builder Status", "builder status"),
        .init("Build", "Stop Builder", "builder stop"), .init("Build", "Delete Builder", "builder delete", destructive: true),
        .init("Networks", "Create Network", "network create", "dev-net"),
        .init("Networks", "Delete Network", "network delete", "dev-net", destructive: true),
        .init("Networks", "Prune Networks", "network prune", destructive: true),
        .init("Networks", "List Networks", "network list", "--format json"), .init("Networks", "Inspect Network", "network inspect", "default"),
        .init("Volumes", "Create Volume", "volume create", "app-data"), .init("Volumes", "Delete Volume", "volume delete", "app-data", destructive: true),
        .init("Volumes", "Prune Volumes", "volume prune", destructive: true), .init("Volumes", "List Volumes", "volume list", "--format json"), .init("Volumes", "Inspect Volume", "volume inspect", "app-data"),
        .init("Registries", "Log In", "registry login", "docker.io", terminal: true), .init("Registries", "Log Out", "registry logout", "docker.io"), .init("Registries", "List Logins", "registry list"),
        .init("Linux Machines", "Create Machine", "machine create", "--name dev --home-mount none ubuntu:24.04"),
        .init("Linux Machines", "Run / Log In", "machine run", "--name dev", terminal: true),
        .init("Linux Machines", "List Machines", "machine list"), .init("Linux Machines", "Inspect Machine", "machine inspect", "dev"),
        .init("Linux Machines", "Change Settings", "machine set", "--name dev cpus=4 memory=4G"),
        .init("Linux Machines", "Set Default Machine", "machine set-default", "dev"),
        .init("Linux Machines", "Machine Logs", "machine logs", "-n 300 dev"), .init("Linux Machines", "Stop Machine", "machine stop", "dev"), .init("Linux Machines", "Delete Machine", "machine delete", "dev", destructive: true),
        .init("System", "Start Engine", "system start", "--enable-kernel-install"), .init("System", "Stop Engine", "system stop", destructive: true),
        .init("System", "Engine Status", "system status"), .init("System", "Version", "system version"),
        .init("System", "Service Logs", "system logs", "--last 5m"), .init("System", "Disk Usage", "system df"),
        .init("System", "Create DNS Domain (Admin)", "system dns create", "test", terminal: true),
        .init("System", "Delete DNS Domain (Admin)", "system dns delete", "test", terminal: true, destructive: true),
        .init("System", "List DNS Domains", "system dns list"), .init("System", "Install Recommended Kernel", "system kernel set", "--recommended"),
        .init("System", "System Properties", "system property list"),
        .init("Kubernetes", "Create Cluster (Experimental)", "k8s create", "--name dev --cpus 2 --memory 4g"),
        .init("Kubernetes", "Delete Cluster", "k8s delete", "--name dev", destructive: true), .init("Kubernetes", "List Clusters", "k8s list"),
        .init("Kubernetes", "Load Image into Cluster", "k8s load-image", "--name dev local/app:dev"),
        .init("Kubernetes", "Write kubeconfig", "k8s write-config", "--name dev")
    ]
}
