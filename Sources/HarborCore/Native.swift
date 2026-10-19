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
            // 1.5.0 prints the address with its prefix length (192.168.64.3/24); the row shows the address.
            let addresses = networks.compactMap { ($0["ipv4Address"] ?? $0["address"]) as? String }.map(Self.address).joined(separator: ", ")
            let resources = config["resources"] as? [String: Any] ?? [:]
            let cpus = (resources["cpus"] as? NSNumber)?.stringValue ?? "?"
            let memory = (resources["memoryInBytes"] as? NSNumber)?.int64Value ?? 0
            let mappings = (config["publishedPorts"] as? [[String: Any]] ?? []).compactMap { port -> PortMapping? in
                guard let host = (port["hostPort"] as? NSNumber)?.intValue, let target = (port["containerPort"] as? NSNumber)?.intValue else { return nil }
                return PortMapping(hostAddress: port["hostAddress"] as? String ?? "", hostPort: host, containerPort: target, transport: (port["proto"] ?? port["protocol"]) as? String ?? "tcp")
            }
            let summary = "\(cpus) CPU · \(ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory))" + (addresses.isEmpty ? "" : " · " + addresses)
            return ContainerRow(id: id, name: id, image: reference, state: state, status: summary, ports: mappings.map(\.label).joined(separator: ", "),
                                portMappings: mappings, details: details(config, status: status, runtimeNetworks: networks))
        }
    }
    private static func details(_ config: [String: Any], status: [String: Any]?, runtimeNetworks: [[String: Any]]) -> ContainerDetails {
        var d = ContainerDetails()
        d.created = date(config["creationDate"])
        d.started = date(status?["startedDate"])
        let process = config["initProcess"] as? [String: Any] ?? [:]
        d.command = ([process["executable"] as? String].compactMap { $0 } + (process["arguments"] as? [String] ?? [])).filter { !$0.isEmpty }
        d.workingDirectory = process["workingDirectory"] as? String ?? ""
        d.environment = process["environment"] as? [String] ?? []
        // `user` is an enum: {"id":{"uid":0,"gid":0}} or {"raw":{"userString":"nginx"}}.
        if let user = process["user"] as? [String: Any] {
            if let raw = user["raw"] as? [String: Any], let name = raw["userString"] as? String { d.user = name }
            else if let ids = user["id"] as? [String: Any], let uid = ids["uid"] as? NSNumber { d.user = uid.stringValue + ((ids["gid"] as? NSNumber).map { ":" + $0.stringValue } ?? "") }
        } else if let user = process["user"] as? String { d.user = user }
        // The mount type is an enum too: {"virtiofs":{}}, {"tmpfs":{}}, {"volume":{"name":…}} or {"block":{…}}.
        d.mounts = (config["mounts"] as? [[String: Any]] ?? []).compactMap { mount in
            guard let destination = mount["destination"] as? String else { return nil }
            let type = mount["type"] as? [String: Any] ?? [:]
            let options = mount["options"] as? [String] ?? []
            var kind = type.keys.sorted().first ?? (mount["type"] as? String ?? "")
            var source = mount["source"] as? String ?? ""
            if kind == "virtiofs" { kind = "bind" }
            if kind == "volume", let name = (type["volume"] as? [String: Any])?["name"] as? String { source = name }
            return ContainerDetails.Mount(kind: kind, source: source, destination: destination, readOnly: options.contains("ro"))
        }
        // Configured networks are known even while stopped; the running ones add their addresses.
        let live = Dictionary(runtimeNetworks.compactMap { n in (n["network"] as? String).map { ($0, n) } }, uniquingKeysWith: { a, _ in a })
        var names = (config["networks"] as? [[String: Any]] ?? []).compactMap { $0["network"] as? String }
        names += live.keys.filter { !names.contains($0) }.sorted()
        d.networks = names.map { name in
            let n = live[name]
            let configured = (config["networks"] as? [[String: Any]])?.first { $0["network"] as? String == name }
            let hostname = (n?["hostname"] as? String) ?? ((configured?["options"] as? [String: Any])?["hostname"] as? String) ?? ""
            return ContainerDetails.Network(name: name, address: ((n?["ipv4Address"] ?? n?["address"]) as? String).map(address) ?? "",
                                            gateway: (n?["ipv4Gateway"] ?? n?["gateway"]) as? String ?? "", hostname: hostname)
        }
        d.labels = config["labels"] as? [String: String] ?? [:]
        if let platform = config["platform"] as? [String: Any], let os = platform["os"] as? String, let arch = platform["architecture"] as? String {
            d.platform = os + "/" + arch
        }
        return d
    }
    /// An address without its prefix length.
    static func address(_ cidr: String) -> String { cidr.split(separator: "/").first.map(String.init) ?? cidr }
    /// 1.5.0 prints ISO 8601 dates; older CLIs printed seconds since 2001-01-01.
    public static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text)
        }
        return (value as? NSNumber).map { Date(timeIntervalSinceReferenceDate: $0.doubleValue) }
    }
    public static func images(_ text: String) throws -> [ImageRow] {
        try objects(text).map { row in
            let config = row["configuration"] as? [String: Any] ?? row
            guard let reference = (config["name"] ?? config["reference"]) as? String else {
                throw HarborError.message("Image JSON is missing a name. Check the raw CLI output.")
            }
            let descriptor = config["descriptor"] as? [String: Any] ?? [:]
            let digest = descriptor["digest"] as? String ?? reference
            // Attestation manifests appear as unknown/unknown variants; they are not part of the image's size.
            let variants = (row["variants"] as? [[String: Any]] ?? []).filter { (($0["platform"] as? [String: Any])?["os"] as? String) != "unknown" }
            let size = variants.reduce(Int64(0)) { $0 + (($1["size"] as? NSNumber)?.int64Value ?? 0) }
            let (repository, tag) = ImageReference.split(reference)
            // The CLI reports the Unix epoch when no variant records a creation time.
            let created = date(config["creationDate"]).flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil }
            return ImageRow(reference: reference, repository: repository, tag: tag, digest: digest,
                            size: size > 0 ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file) : "—", created: created)
        }
    }
    /// `container stats --format json` rows; CPU time is cumulative, so a percentage needs two samples.
    public static func stats(_ text: String) throws -> [ContainerStats] {
        try JSONDecoder().decode([ContainerStats].self, from: Data(text.utf8))
    }
}

/// Shell-like argument splitting only: no evaluation, expansion, redirects, or pipelines.
public enum ArgumentTokenizer {
    public static func split(_ text: String) throws -> [String] {
        var tokens: [String] = [], current = "", quote: Character?, escape = false, active = false
        for c in text {
            if escape {
                // As in POSIX shells, inside double quotes a backslash only escapes \ " $ and `.
                if quote == "\"" && !"\\\"$`".contains(c) { current.append("\\") }
                current.append(c); escape = false; active = true; continue
            }
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
    /// Interactive: always handed to Terminal.
    public let terminal: Bool
    /// Stops services or deletes resources: asks for confirmation first.
    public let destructive: Bool
    /// Runs with sudo in Terminal, where macOS asks for the password; the app never sees it.
    public let admin: Bool
    public var id: String { path.joined(separator: " ") }
    public init(_ group: String, _ title: String, _ path: String, _ example: String = "", terminal: Bool = false, destructive: Bool = false, admin: Bool = false) {
        self.group = group; self.title = title; self.path = path.split(separator: " ").map(String.init)
        self.example = example; self.terminal = terminal; self.destructive = destructive; self.admin = admin
    }
    /// Catalog groups in display order.
    public static let groups: [String] = { var seen = Set<String>(); return all.map(\.group).filter { seen.insert($0).inserted } }()
    public static func operations(in group: String) -> [NativeOperation] { all.filter { $0.group == group } }
    public static func named(_ id: String) -> NativeOperation? { all.first { $0.id == id } }
    /// The example arguments aimed at a listed resource: every catalog example ends with the resource's name.
    public func example(naming resource: String) -> String {
        (example.split(separator: " ").dropLast().map(String.init) + [Command.quote(resource)]).joined(separator: " ")
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
        .init("System", "Create DNS Domain (Admin)", "system dns create", "test", terminal: true, admin: true),
        .init("System", "Delete DNS Domain (Admin)", "system dns delete", "test", terminal: true, destructive: true, admin: true),
        .init("System", "List DNS Domains", "system dns list"), .init("System", "Install Recommended Kernel", "system kernel set", "--recommended"),
        .init("System", "System Properties", "system property list"),
        .init("Kubernetes", "Create Cluster (Experimental)", "k8s create", "--name dev --cpus 2 --memory 4g"),
        .init("Kubernetes", "Delete Cluster", "k8s delete", "--name dev", destructive: true), .init("Kubernetes", "List Clusters", "k8s list"),
        .init("Kubernetes", "Load Image into Cluster", "k8s load-image", "--name dev local/app:dev"),
        .init("Kubernetes", "Write kubeconfig", "k8s write-config", "--name dev")
    ]
}
