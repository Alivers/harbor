import Foundation
import HarborCore

final class HarborCoreTests {
    func testNativeManagedContainerAndLegacyState() throws {
        let row = #"{"configuration":{"id":"web","image":{"reference":"nginx:alpine"},"resources":{"cpus":2,"memoryInBytes":1073741824},"publishedPorts":[{"hostPort":8080,"containerPort":80}]},"status":{"state":"running","networks":[]}}"#
        let containers = try NativeParser.containers("[" + row + "]")
        XCTAssertEqual(containers[0].name, "web")
        XCTAssertTrue(containers[0].running)
        XCTAssertTrue(containers[0].ports.contains("8080"))
        XCTAssertEqual(containers[0].portMappings.first?.url?.absoluteString, "http://localhost:8080")
        let bound = PortMapping(hostAddress: "127.0.0.1", hostPort: 5353, containerPort: 53, transport: "UDP")
        XCTAssertNil(bound.url); XCTAssertEqual(bound.label, "5353 → 53/udp")
        XCTAssertEqual(PortMapping(hostAddress: "::1", hostPort: 8443, containerPort: 443).url?.absoluteString, "https://[::1]:8443")
        XCTAssertEqual(PortMapping(hostPort: 9443, containerPort: 443).url?.absoluteString, "https://localhost:9443")
        XCTAssertEqual(PortMapping(hostPort: 8080, containerPort: 80).url?.absoluteString, "http://localhost:8080")
        let legacy = #"[{"configuration":{"id":"web","image":{"reference":"nginx:alpine"}},"status":"stopped"}]"#
        XCTAssertEqual(try NativeParser.containers(legacy)[0].state, "stopped")
        XCTAssertThrowsError(try NativeParser.containers("[{}]"))
    }
    func testNativeImagesPreserveRegistryPort() throws {
        let input = #"[{"configuration":{"name":"localhost:5000/team/app:dev","descriptor":{"digest":"sha256:abc"}},"variants":[{"size":1024}]}]"#
        let image = try NativeParser.images(input)[0]
        XCTAssertEqual(image.reference, "localhost:5000/team/app:dev")
        XCTAssertEqual(image.repository, "localhost:5000/team/app")
        XCTAssertEqual(image.tag, "dev")
        XCTAssertEqual(image.digest, "sha256:abc")
        XCTAssertThrowsError(try NativeParser.images("{}"))
    }
    func testImageReferencesKeepPortsAndDigests() {
        func check(_ reference: String, _ repository: String, _ tag: String) {
            let parts = ImageReference.split(reference)
            XCTAssertEqual(parts.repository, repository); XCTAssertEqual(parts.tag, tag)
        }
        check("nginx", "nginx", "latest")
        check("nginx:alpine", "nginx", "alpine")
        check("localhost:5000/app", "localhost:5000/app", "latest")
        check("ghcr.io/team/app@sha256:abc", "ghcr.io/team/app", "<none>")
        check("app:1.0@sha256:abc", "app", "1.0")
        XCTAssertTrue(ImageReference.isValid("localhost:5000/app:dev"))
        XCTAssertFalse(ImageReference.isValid("") || ImageReference.isValid("--privileged") || ImageReference.isValid("a b"))
    }
    func testNativeBackendDoesNotUseDocker() {
        let config = RuntimeConfig(docker: "/missing/docker", container: "/native/container")
        let command = config.nativeCommand(["list", "--all", "--format", "json"])
        XCTAssertEqual(command.executable, "/native/container")
        XCTAssertEqual(command.arguments, ["list", "--all", "--format", "json"])
    }
    func testTokenizerDoesNotEvaluateShell() throws {
        XCTAssertEqual(try ArgumentTokenizer.split(#"--env 'MESSAGE=hello world' '' \"literal\" '$HOME'"#), ["--env", "MESSAGE=hello world", "", "\"literal\"", "$HOME"])
        XCTAssertEqual(try ArgumentTokenizer.split("a\\ b c"), ["a b", "c"])
        // Inside double quotes a backslash escapes only \ " $ and ` (POSIX), so Windows-style paths survive.
        XCTAssertEqual(try ArgumentTokenizer.split(#""C:\path" "say \"hi\"" 'a\b'"#), [#"C:\path"#, #"say "hi""#, #"a\b"#])
        XCTAssertThrowsError(try ArgumentTokenizer.split("'unclosed"))
        XCTAssertThrowsError(try ArgumentTokenizer.split("trailing\\"))
    }
    func testNativeCatalogIncludesAllFeatureGroups() {
        let groups = Set(NativeOperation.all.map(\.group))
        XCTAssertEqual(groups, Set(["Containers", "Images", "Build", "Networks", "Volumes", "Registries", "Linux Machines", "System", "Kubernetes"]))
        XCTAssertEqual(Set(NativeOperation.all.map(\.id)).count, NativeOperation.all.count)
        XCTAssertEqual(NativeOperation.groups.first, "Containers")
        XCTAssertEqual(NativeOperation.operations(in: "Kubernetes").count, 5)
        XCTAssertEqual(NativeOperation.all.count, 68)
        XCTAssertEqual(NativeOperation.named("commit")?.group, "Containers")
        // sudo is only ever typed into Terminal, never run by the app.
        XCTAssertEqual(NativeOperation.all.filter(\.admin).map(\.id), ["system dns create", "system dns delete"])
        XCTAssertTrue(NativeOperation.all.filter(\.admin).allSatisfy(\.terminal))
    }
    func testNativeHelpRejectsFallbackRootHelp() {
        XCTAssertTrue(NativeHelp.matches("USAGE: container volume create [options]", path: ["volume", "create"]))
        XCTAssertTrue(NativeHelp.matches("USAGE: k8s create [options]", path: ["k8s", "create"]))
        XCTAssertEqual(NativeHelp.matches("USAGE: container [--debug] <subcommand>", path: ["volume", "create"]), false)
        // 1.6.0 moved build and builder into plugins; 1.5.0 printed the dispatcher's name.
        XCTAssertTrue(NativeHelp.matches("USAGE: build [<options>] [<context-dir>]", path: ["build"]))
        XCTAssertTrue(NativeHelp.matches("USAGE: container build [<options>] [<context-dir>]", path: ["build"]))
        XCTAssertTrue(NativeHelp.matches("USAGE: builder start [--cpus <cpus>]", path: ["builder", "start"]))
        XCTAssertFalse(NativeHelp.matches("USAGE: builder <subcommand>", path: ["builder", "start"]))
        XCTAssertFalse(NativeHelp.matches("USAGE: volume create", path: ["volume", "create"]))
    }
    func testDockerAlwaysTargetsExplicitSocket() {
        let config = RuntimeConfig(docker: "/bin/docker", container: "/bin/container", socktainer: "/bin/socktainer", socket: "/tmp/harbor socket")
        let command = config.dockerCommand(["ps", "--all"])
        XCTAssertEqual(command.arguments, ["--host", "unix:///tmp/harbor socket", "ps", "--all"])
        XCTAssertNil(command.environment["DOCKER_CONTEXT"])
        XCTAssertNil(command.environment["DOCKER_TLS_VERIFY"])
        XCTAssertEqual(command.environment["DOCKER_HOST"], "unix:///tmp/harbor socket")
        // An import source is named by its own socket, never by an inherited context.
        let source = config.dockerCommand(DockerImport.listArguments, socket: "/Users/me/.orbstack/run/docker.sock")
        XCTAssertEqual(Array(source.arguments.prefix(2)), ["--host", "unix:///Users/me/.orbstack/run/docker.sock"])
        XCTAssertEqual(source.environment["DOCKER_HOST"], "unix:///Users/me/.orbstack/run/docker.sock")
        XCTAssertNil(source.environment["DOCKER_CONTEXT"])
    }
    func testComposePreservesOverrideOrderAndWorkingDirectory() {
        let files = ["/tmp/project with spaces/compose.yaml", "/tmp/project with spaces/dev.override.yaml"]
        let project = ComposeProject(files: files)
        let command = RuntimeConfig().composeCommand(project, ["up", "--detach"])
        XCTAssertEqual(command.directory, "/tmp/project with spaces")
        XCTAssertEqual(Array(command.arguments.suffix(6)), ["--file", files[0], "--file", files[1], "up", "--detach"])
        XCTAssertTrue(command.arguments.contains("--project-directory"))
    }
    func testComposeDirectoryFollowsFileOrder() {
        var project = ComposeProject(files: ["/srv/app/compose.yaml", "/srv/overrides/dev.yaml"])
        project.files.swapAt(0, 1)
        let command = RuntimeConfig().composeCommand(project, ComposeAction.start.arguments)
        XCTAssertEqual(command.directory, "/srv/overrides")
        XCTAssertEqual(Array(command.arguments.drop { $0 != "--project-directory" }.prefix(2)), ["--project-directory", "/srv/overrides"])
        XCTAssertEqual(ComposeAction.start.arguments, ["up", "--detach"])
        XCTAssertFalse(ComposeAction.validate.needsDocker)
        XCTAssertTrue(ComposeAction.allCases.filter { $0 != .validate }.allSatisfy(\.needsDocker))
    }
    func testDockerJSONLinesAndArray() throws {
        let row = #"{"ID":"abc","Names":"web","Image":"nginx:alpine","State":"running","Status":"Up 4 minutes","Ports":"127.0.0.1:8080->80/tcp"}"#
        let lines = try JSONRows.decode(ContainerRow.self, from: row + "\n" + row)
        XCTAssertEqual(lines.count, 2); XCTAssertTrue(lines[0].running)
        XCTAssertEqual(try JSONRows.decode(ContainerRow.self, from: "[" + row + "]").count, 1)
        XCTAssertEqual(try JSONRows.decode(ContainerRow.self, from: "\n").count, 0)
        XCTAssertThrowsError(try JSONRows.decode(ContainerRow.self, from: "backend failed"))
        // `docker compose ps --format json` (Compose 5.6) adds fields and nests arrays; unknown keys are ignored.
        let service = #"{"Command":"\"nginx\"","ExitCode":0,"ID":"aaaaaaaaaaaa","Image":"nginx:alpine","Name":"harbor-smoke-web-1","Names":"harbor-smoke-web-1","Ports":"127.0.0.1:18080->80/tcp","Project":"harbor-smoke","Publishers":[{"URL":"127.0.0.1","TargetPort":80,"PublishedPort":18080,"Protocol":"tcp"}],"Service":"web","State":"running","Status":"Up 2 minutes"}"#
        let services = try JSONRows.decode(ContainerRow.self, from: service + "\n")
        XCTAssertEqual(services.map(\.name), ["harbor-smoke-web-1"]); XCTAssertTrue(services[0].running)
        XCTAssertEqual(services[0].portMappings.map(\.url?.absoluteString), ["http://127.0.0.1:18080"])
        XCTAssertEqual(services[0].service, "web"); XCTAssertEqual(lines[0].service, "")
    }
    func testRunArgumentsKeepEnvironmentLiteral() throws {
        var options = RunOptions(image: " nginx:alpine "); options.environment = ["TOKEN=$(touch /tmp/should-never-exist)", "GREETING=hello world", "  "]
        let args = try options.arguments()
        XCTAssertTrue(args.contains("TOKEN=$(touch /tmp/should-never-exist)"))
        XCTAssertTrue(args.contains("GREETING=hello world"))
        XCTAssertEqual(args.last, "nginx:alpine")
        XCTAssertNil(options.problem)
        XCTAssertTrue(RunOptions().problem?.contains("image") == true)
        options.image = "--privileged"; XCTAssertThrowsError(try options.arguments())
        options.image = "nginx"; options.environment = ["invalid"]; XCTAssertThrowsError(try options.arguments())
        var ports = RunOptions(image: "nginx"); ports.ports = ["127.0.0.1:8080:80", " 8443:443/tcp ", "", "[::1]:9000:9000"]; ports.volumes = ["/srv/data:/data"]
        let portArgs = try ports.arguments()
        XCTAssertEqual(zip(portArgs, portArgs.dropFirst()).filter { $0.0 == "--publish" }.map(\.1), ["127.0.0.1:8080:80", "8443:443/tcp", "[::1]:9000:9000"])
        XCTAssertTrue(portArgs.contains("/srv/data:/data"))
        ports.ports = ["8080"]; XCTAssertTrue(ports.problem?.contains("8080") == true)
        ports.ports = []; ports.volumes = ["data"]; XCTAssertNotNil(ports.problem)
        ports.volumes = []; ports.extraOptions = "--label 'open"; XCTAssertNotNil(ports.problem)
    }
    func testNativeDetailsAndStatsFrom150() throws {
        // `container list --all --format json` as 1.5.0 prints it (keys from the upstream encoders).
        let element = #"{"configuration":{"capAdd":[],"capDrop":[],"creationDate":"2026-10-19T08:58:41Z","id":"web","image":{"descriptor":{"digest":"sha256:5ed8","size":10229},"reference":"docker.io/library/nginx:latest"},"initProcess":{"arguments":["nginx","-g","daemon off;"],"environment":["PATH=/usr/bin","NGINX_VERSION=1.27.5"],"executable":"/docker-entrypoint.sh","rlimits":[],"supplementalGroups":[],"terminal":false,"user":{"id":{"gid":0,"uid":0}},"workingDirectory":"/"},"labels":{"com.example.role":"frontend"},"mounts":[{"destination":"/usr/share/nginx/html","options":["ro"],"source":"/Users/me/site","type":{"virtiofs":{}}},{"destination":"/data","options":[],"source":"/Users/me/Library/Application Support/com.apple.container/volumes/pgdata/volume.img","type":{"volume":{"cache":{"on":{}},"format":"ext4","name":"pgdata","sync":{"fsync":{}}}}},{"destination":"/tmp","options":["size=67108864"],"source":"tmpfs","type":{"tmpfs":{}}}],"networks":[{"network":"default","options":{"hostname":"web.test.","mtu":1280}}],"platform":{"architecture":"arm64","os":"linux","variant":"v8"},"publishedPorts":[{"containerPort":80,"count":1,"hostAddress":"0.0.0.0","hostPort":8080,"proto":"tcp"}],"publishedSockets":[],"readOnly":false,"resources":{"cpuOverhead":1,"cpus":4,"memoryInBytes":1073741824},"rosetta":false,"runtimeHandler":"container-runtime-linux","ssh":false,"sysctls":{},"useInit":false,"virtualization":false},"id":"web","status":{"networks":[{"hostname":"web.test.","ipv4Address":"192.168.64.3/24","ipv4Gateway":"192.168.64.1","macAddress":"ae:4f:12:9c:01:7d","mtu":1280,"network":"default"}],"startedDate":"2026-10-19T08:58:43Z","state":"running"}}"#
        let row = try NativeParser.containers("[" + element + "]")[0]
        XCTAssertTrue(row.running); XCTAssertTrue(row.status.hasSuffix("192.168.64.3"))
        XCTAssertEqual(row.portMappings.first?.url?.absoluteString, "http://localhost:8080")
        let d = try XCTUnwrap(row.details)
        XCTAssertEqual(d.created, ISO8601DateFormatter().date(from: "2026-10-19T08:58:41Z"))
        XCTAssertNotNil(d.started)
        XCTAssertEqual(d.command, ["/docker-entrypoint.sh", "nginx", "-g", "daemon off;"])
        XCTAssertEqual(d.user, "0:0"); XCTAssertEqual(d.workingDirectory, "/"); XCTAssertEqual(d.platform, "linux/arm64")
        XCTAssertEqual(d.environment, ["PATH=/usr/bin", "NGINX_VERSION=1.27.5"])
        XCTAssertEqual(d.mounts.map(\.kind), ["bind", "volume", "tmpfs"])
        XCTAssertEqual(d.mounts[0].readOnly, true); XCTAssertEqual(d.volumeNames, ["pgdata"])
        XCTAssertEqual(d.networks, [ContainerDetails.Network(name: "default", address: "192.168.64.3", gateway: "192.168.64.1", hostname: "web.test.")])
        XCTAssertEqual(d.labels, ["com.example.role": "frontend"])
        // A stopped container still names its configured networks; a raw user string is kept as typed.
        let stopped = element.replacingOccurrences(of: #""state":"running""#, with: #""state":"stopped""#)
            .replacingOccurrences(of: #""networks":[{"hostname":"web.test.","ipv4Address":"192.168.64.3/24","ipv4Gateway":"192.168.64.1","macAddress":"ae:4f:12:9c:01:7d","mtu":1280,"network":"default"}]"#, with: #""networks":[]"#)
            .replacingOccurrences(of: #"{"id":{"gid":0,"uid":0}}"#, with: #"{"raw":{"userString":"nginx"}}"#)
        let s = try XCTUnwrap(try NativeParser.containers("[" + stopped + "]")[0].details)
        XCTAssertEqual(s.networks.map(\.name), ["default"]); XCTAssertEqual(s.networks[0].address, ""); XCTAssertEqual(s.user, "nginx")
        // Older CLIs printed reference-date seconds.
        XCTAssertEqual(NativeParser.date(NSNumber(value: 0)), Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertNotNil(NativeParser.date("2025-05-08T22:27:23.123Z"))
        // Images: creation date, attestation variants left out of the size, epoch meaning "unknown".
        let images = try NativeParser.images(#"[{"configuration":{"creationDate":"2025-05-08T22:27:23Z","descriptor":{"digest":"sha256:a856"},"name":"docker.io/library/alpine:3.20"},"id":"a856","variants":[{"platform":{"architecture":"arm64","os":"linux"},"size":4096},{"platform":{"architecture":"unknown","os":"unknown"},"size":999999}]},{"configuration":{"creationDate":"1970-01-01T00:00:00Z","descriptor":{"digest":"sha256:b"},"name":"local/app:dev"},"id":"b","variants":[]}]"#)
        XCTAssertEqual(images[0].size, ByteCountFormatter.string(fromByteCount: 4096, countStyle: .file))
        XCTAssertNotNil(images[0].created); XCTAssertNil(images[1].created)
        XCTAssertTrue(ImageReference.sameImage("docker.io/library/nginx:latest", "nginx"))
        XCTAssertTrue(ImageReference.sameImage("docker.io/team/app:1", "team/app:1"))
        XCTAssertFalse(ImageReference.sameImage("nginx:alpine", "nginx"))
        XCTAssertFalse(ImageReference.sameImage("ghcr.io/team/app:1", "team/app:1"))
        // Stats: cumulative counters; the percentage comes from two samples.
        let first = try NativeParser.stats(#"[{"blockReadBytes":4718592,"cpuUsageUsec":1000000,"id":"web","memoryLimitBytes":1073741824,"memoryUsageBytes":47431680,"networkRxBytes":1000,"networkTxBytes":500,"numProcesses":3}]"#)[0]
        let second = try NativeParser.stats(#"[{"cpuUsageUsec":2000000,"id":"web","memoryUsageBytes":50000000,"networkRxBytes":3000}]"#)[0]
        XCTAssertEqual(ContainerStats.cpuPercent(from: first, to: second, interval: 2), 50)
        XCTAssertEqual(ContainerStats.rate(first.networkRxBytes, second.networkRxBytes, interval: 2), 1000)
        XCTAssertNil(ContainerStats.rate(first.networkTxBytes, second.networkTxBytes, interval: 2))
        XCTAssertEqual(try NativeParser.stats("[]\n").count, 0)
    }
    func testRunFormOptionalFlags() throws {
        var options = RunOptions(image: "nginx:alpine")
        options.network = "dev-net"; options.removeWhenStopped = true; options.architecture = "amd64"
        options.workingDirectory = "/app"; options.entrypoint = "/bin/sh"; options.user = "1000:1000"
        options.labels = ["team=web", " "]; options.useInit = true; options.readOnly = true
        let args = try options.arguments()
        func value(after flag: String) -> String? { zip(args, args.dropFirst()).first { $0.0 == flag }?.1 }
        XCTAssertEqual(value(after: "--network"), "dev-net"); XCTAssertEqual(value(after: "--arch"), "amd64")
        XCTAssertEqual(value(after: "--workdir"), "/app"); XCTAssertEqual(value(after: "--entrypoint"), "/bin/sh")
        XCTAssertEqual(value(after: "--user"), "1000:1000"); XCTAssertEqual(value(after: "--label"), "team=web")
        XCTAssertTrue(args.contains("--rm") && args.contains("--init") && args.contains("--read-only"))
        XCTAssertEqual(args.last, "nginx:alpine")
        // Every optional flag the form emits is one it gates on the local help.
        XCTAssertTrue(args.filter { $0.hasPrefix("--") }.allSatisfy { ["--detach", "--cpus", "--memory", "--name"].contains($0) || RunOptions.optionalFlags.contains($0) })
        XCTAssertFalse(try RunOptions(image: "nginx").arguments().contains("--rm"))
        options.workingDirectory = "app"; XCTAssertNotNil(options.problem); options.workingDirectory = ""
        options.entrypoint = "--privileged"; XCTAssertNotNil(options.problem); options.entrypoint = ""
        options.user = "root user"; XCTAssertNotNil(options.problem); options.user = ""
        options.network = "a b"; XCTAssertNotNil(options.problem); options.network = ""
        options.architecture = "riscv"; XCTAssertNotNil(options.problem); options.architecture = ""
        options.labels = ["novalue"]; XCTAssertNotNil(options.problem)
    }
    func testBuildNetworkAndVolumeForms() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-build-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let dockerfile = folder + "/Dockerfile.dev"
        _ = FileManager.default.createFile(atPath: dockerfile, contents: Data("FROM scratch\n".utf8))
        var build = BuildOptions(dropped: dockerfile)
        XCTAssertEqual(build.context, folder); XCTAssertEqual(build.dockerfile, dockerfile)
        XCTAssertTrue(build.problem?.contains("tag") == true)
        build.tags = ["local/app:dev", ""]; build.buildArgs = ["VERSION=1 2"]; build.target = "prod"; build.platform = "linux/amd64"; build.noCache = true
        XCTAssertEqual(try build.arguments(), ["build", "--progress", "plain", "--tag", "local/app:dev", "--file", dockerfile, "--build-arg", "VERSION=1 2",
                                               "--target", "prod", "--platform", "linux/amd64", "--no-cache", folder])
        XCTAssertEqual(BuildOptions(dropped: folder).context, folder); XCTAssertEqual(BuildOptions(dropped: folder).dockerfile, "")
        build.context = "relative"; XCTAssertNotNil(build.problem)
        var network = NetworkOptions(); network.name = "dev-net"; network.subnet = "192.168.100.0/24"; network.hostOnly = true
        XCTAssertEqual(try network.arguments(), ["network", "create", "--internal", "--subnet", "192.168.100.0/24", "dev-net"])
        network.subnet = "192.168.100.0"; XCTAssertNotNil(network.problem)
        network.subnet = ""; network.name = "-x"; XCTAssertThrowsError(try network.arguments())
        var volume = VolumeOptions(); volume.name = "app-data"; volume.size = "10g"; volume.labels = ["tier=db"]
        XCTAssertEqual(try volume.arguments(), ["volume", "create", "-s", "10g", "--label", "tier=db", "app-data"])
        volume.size = "ten"; XCTAssertNotNil(volume.problem)
    }
    func testComposeActionsTargetServices() {
        XCTAssertEqual(ComposeAction.restart.arguments(service: "web"), ["restart", "web"])
        XCTAssertEqual(ComposeAction.start.arguments(service: "web"), ["up", "--detach", "web"])
        XCTAssertEqual(ComposeAction.logs.arguments(service: "db"), ["logs", "--no-color", "--tail", "300", "db"])
        XCTAssertEqual(ComposeAction.down.arguments(service: "web"), ["down"])
        XCTAssertEqual(ComposeAction.downWithVolumes.arguments, ["down", "--volumes"])
        XCTAssertEqual(ComposeAction.pull.arguments(service: ""), ["pull"])
        XCTAssertTrue(ComposeAction.down.destructive && ComposeAction.downWithVolumes.destructive && !ComposeAction.stop.destructive)
    }
    func testContainerFilesAndDockerImport() throws {
        XCTAssertEqual(ContainerFiles.parse("./\n../\nbin/\n.env\nApp.log\napp/\nmy file.txt\n").map(\.name), ["app", "bin", ".env", "App.log", "my file.txt"])
        XCTAssertEqual(ContainerFiles.parse("etc/\n").first?.isDirectory, true)
        XCTAssertEqual(ContainerFiles.listArguments(container: "web", path: "/etc"), ["exec", "web", "ls", "-1Ap", "/etc"])
        XCTAssertEqual(ContainerFiles.normalize("/var//log/../lib/./x/"), "/var/lib/x")
        XCTAssertEqual(ContainerFiles.normalize("/.."), "/"); XCTAssertNil(ContainerFiles.normalize("etc"))
        XCTAssertEqual(ContainerFiles.join("/", "etc"), "/etc"); XCTAssertEqual(ContainerFiles.join("/etc", "hosts"), "/etc/hosts")
        XCTAssertEqual(ContainerFiles.parent(of: "/etc/nginx"), "/etc"); XCTAssertEqual(ContainerFiles.parent(of: "/etc"), "/"); XCTAssertEqual(ContainerFiles.parent(of: "/"), "/")
        XCTAssertEqual(try ContainerFiles.downloadArguments(container: "web", path: "/etc/hosts", to: "/Users/me/Downloads"), ["copy", "web:/etc/hosts", "/Users/me/Downloads"])
        XCTAssertEqual(try ContainerFiles.uploadArguments("/Users/me/a.txt", container: "web", folder: "/tmp"), ["copy", "/Users/me/a.txt", "web:/tmp/"])
        XCTAssertEqual(try ContainerFiles.uploadArguments("/Users/me/a.txt", container: "web", folder: "/"), ["copy", "/Users/me/a.txt", "web:/"])
        XCTAssertThrowsError(try ContainerFiles.uploadArguments("/Users/me/a:b.txt", container: "web", folder: "/tmp"))
        // `docker image ls --format json` as printed by Docker 29: one object per line.
        let listing = #"{"Containers":"0","CreatedSince":"2 days ago","ID":"04b28d4aff67","Repository":"swift","Size":"4.48GB","Tag":"6.1-noble"}"# + "\n" +
            #"{"Containers":"0","ID":"aaaa","Repository":"<none>","Size":"1MB","Tag":"<none>"}"#
        let images = try DockerImport.images(listing)
        XCTAssertEqual(images.map(\.reference), ["swift:6.1-noble"]); XCTAssertEqual(images[0].size, "4.48GB")
        XCTAssertEqual(DockerImport.saveArguments("swift:6.1-noble", to: "/tmp/x.tar"), ["image", "save", "--output", "/tmp/x.tar", "swift:6.1-noble"])
        XCTAssertEqual(DockerImport.loadArguments("/tmp/x.tar"), ["image", "load", "--input", "/tmp/x.tar"])
        XCTAssertEqual(DockerImport.candidates(home: "/Users/me").first?.socket, "/Users/me/.orbstack/run/docker.sock")
    }
    func testTextTablesAndResourceHelpers() {
        let table = TextTable.parse("NETWORK  STATE    SUBNET\ndefault  running  192.168.64.0/24\ndev-net  stopped\n")
        XCTAssertEqual(table?.columns, ["NETWORK", "STATE", "SUBNET"])
        XCTAssertEqual(table?.rows, [["default", "running", "192.168.64.0/24"], ["dev-net", "stopped", ""]])
        XCTAssertEqual(TextTable.parse("CONTAINER ID   IMAGE\nabc            nginx:alpine")?.columns, ["CONTAINER ID", "IMAGE"])
        XCTAssertEqual(TextTable.parse("NAME  STATE\n")?.rows.count, 0)
        XCTAssertNil(TextTable.parse("No machines found."))
        XCTAssertNil(TextTable.parse("NAME  STATE\nverylongname state"))
        XCTAssertNil(TextTable.parse(""))
        XCTAssertEqual(NativeOperation.named("network delete")?.example(naming: "dev net"), "'dev net'")
        XCTAssertEqual(NativeOperation.named("machine logs")?.example(naming: "box"), "-n 300 box")
        XCTAssertEqual(NativeOperation.named("k8s delete")?.example(naming: "lab"), "--name lab")
        XCTAssertEqual(JSONText.pretty(#"{"b":1,"a":[true]}"#), "{\n  \"a\" : [\n    true\n  ],\n  \"b\" : 1\n}")
        XCTAssertEqual(JSONText.pretty("not json"), "not json")
    }
    func testContainerFeaturesFrom160() throws {
        // 1.6.0 keeps DNS aliases with the attachment's options.
        let element = #"{"configuration":{"id":"gateway","image":{"reference":"nginx:latest"},"networks":[{"network":"default","options":{"aliases":["api.test",".gateway.test"],"hostname":"gateway.test."}}]},"status":{"networks":[{"hostname":"gateway.test.","ipv4Address":"192.168.64.5/24","ipv4Gateway":"192.168.64.1","network":"default"}],"state":"running"}}"#
        let network = try XCTUnwrap(try NativeParser.containers("[" + element + "]")[0].details?.networks.first)
        XCTAssertEqual(network.aliases, ["api.test", ".gateway.test"]); XCTAssertEqual(network.address, "192.168.64.5")
        // Aliases ride on --network, on the default network when none is chosen.
        var options = RunOptions(image: "nginx:latest"); options.aliases = ["api.test", " .gateway.test ", ""]
        let args = try options.arguments()
        XCTAssertEqual(zip(args, args.dropFirst()).first { $0.0 == "--network" }?.1, "default,alias=api.test,alias=.gateway.test")
        options.network = "dev-net"; XCTAssertTrue(try options.arguments().contains("dev-net,alias=api.test,alias=.gateway.test"))
        options.aliases = []; XCTAssertTrue(try options.arguments().contains("dev-net"))
        XCTAssertFalse(try RunOptions(image: "nginx").arguments().contains("--network"))
        for bad in ["*.gateway.test", "api.test,mac=02:42:ac:11:00:02", "a b", "..test", "api..test", "-api.test", "_svc.test", "svc_.test", String(repeating: "a", count: 64) + ".test"] {
            options.aliases = [bad]; XCTAssertNotNil(options.problem)
        }
        options.aliases = Array(repeating: "api.test", count: RunOptions.maxAliases + 1); XCTAssertNotNil(options.problem)
        options.aliases = ["api", "web.test.", "svc_a.test", String(repeating: "a", count: 63) + ".test"]; XCTAssertNil(options.problem)
        // image list: 1.6.0 prints what it can read, then exits nonzero.
        let listing = #"[{"configuration":{"name":"nginx:alpine","descriptor":{"digest":"sha256:a"}},"variants":[]}]"#
        let partial = try NativeParser.imageListing(output: listing, errorOutput: "Error: failed to read 1 image(s)\n", status: 1)
        XCTAssertEqual(partial.rows.map(\.reference), ["nginx:alpine"]); XCTAssertEqual(partial.skipped, "Error: failed to read 1 image(s)")
        XCTAssertNil(try NativeParser.imageListing(output: listing, errorOutput: "", status: 0).skipped)
        XCTAssertThrowsError(try NativeParser.imageListing(output: "", errorOutput: "XPC connection error", status: 1))
        // commit
        XCTAssertEqual(try ContainerCommit.arguments(container: "web", reference: "local/web:v2"), ["commit", "web", "local/web:v2"])
        XCTAssertEqual(ContainerCommit.suggestedReference(for: "Web"), "local/web:snapshot")
        for bad in ["", "local/web:", "--force", "a b", "web@sha256:abc"] { XCTAssertThrowsError(try ContainerCommit.arguments(container: "web", reference: bad)) }
    }
    func testKubernetesClusters() throws {
        var options = ClusterOptions()
        XCTAssertEqual(try options.arguments(), ["k8s", "create", "--name", "k8s-dev"])
        options.name = "lab"; options.workers = 2; options.cpus = 4; options.memory = "8g"; options.network = .none; options.removeWhenStopped = true
        XCTAssertEqual(try options.arguments(), ["k8s", "create", "--name", "lab", "--workers", "2", "--cpus", "4", "--memory", "8g", "--cni", "NONE", "--rm"])
        options.network = .manifest; options.manifest = "/does/not/exist.yaml"; XCTAssertNotNil(options.problem)
        options.manifest = "relative.yaml"; XCTAssertNotNil(options.problem)
        options.network = .bundled; options.nodeImage = "kindest/node:v1.35.5"
        XCTAssertEqual(Array(try options.arguments().suffix(3)), ["--node-image", "kindest/node:v1.35.5", "--rm"])
        options.workers = ClusterOptions.maxWorkers + 1; XCTAssertNotNil(options.problem); options.workers = 0
        options.memory = "lots"; XCTAssertNotNil(options.problem); options.memory = ""
        options.name = "-x"; XCTAssertThrowsError(try options.arguments())
        // `k8s list` prints one row per node; clusters keep their nodes in order.
        let listing = """
        CLUSTER  NODE              ROLE           STATE    CPUS  MEMORY   ADDR           PORTS
        k8s-dev  k8s-dev           control-plane  running  2     4096 MB  192.168.64.10  6443->6443
        k8s-dev  k8s-dev-worker-1  worker         running  2     4096 MB  192.168.64.11
        lab      lab               control-plane  stopped  2     4096 MB
        """
        XCTAssertEqual(KubernetesClusters.parse(listing), [.init(name: "k8s-dev", nodes: ["k8s-dev", "k8s-dev-worker-1"]), .init(name: "lab", nodes: ["lab"])])
        XCTAssertEqual(KubernetesClusters.parse("No clusters found."), [])
        XCTAssertEqual(try KubernetesClusters.loadArguments(image: "local/app:dev", cluster: "k8s-dev"), ["k8s", "load-image", "--name", "k8s-dev", "local/app:dev"])
        XCTAssertEqual(try KubernetesClusters.loadArguments(image: "app", cluster: "k8s-dev", nodes: ["k8s-dev-worker-1"]),
                       ["k8s", "load-image", "--name", "k8s-dev", "--node", "k8s-dev-worker-1", "app"])
        XCTAssertThrowsError(try KubernetesClusters.loadArguments(image: "--all", cluster: "k8s-dev"))
    }
    func testReleaseVersions() throws {
        XCTAssertEqual(ReleaseVersion.cli("container CLI version 1.6.0 (build: release, commit: ca4884f)"), "1.6.0")
        XCTAssertEqual(ReleaseVersion.cli("container CLI version v1.10.2 (build: debug)"), "1.10.2")
        XCTAssertNil(ReleaseVersion.cli("command not found"))
        XCTAssertTrue(ReleaseVersion.isNewer("1.6.0", than: "1.5.0")); XCTAssertTrue(ReleaseVersion.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(ReleaseVersion.isNewer("1.6.1", than: "1.6")); XCTAssertTrue(ReleaseVersion.isNewer("v2.0.0", than: "1.99"))
        XCTAssertFalse(ReleaseVersion.isNewer("1.6.0", than: "1.6.0")); XCTAssertFalse(ReleaseVersion.isNewer("1.6", than: "1.6.0"))
        XCTAssertFalse(ReleaseVersion.isNewer("1.5.0", than: "1.6.0"))
        XCTAssertEqual(ReleaseVersion.notes("1.6.0").absoluteString, "https://github.com/apple/container/releases/tag/1.6.0")
        // Homebrew links its bin into the Cellar; the official installer puts a plain file in /usr/local/bin.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-brew-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cellar = root.appendingPathComponent("Cellar/container/1.6.0/bin"), bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: cellar.appendingPathComponent("container").path, contents: Data())
        _ = FileManager.default.createFile(atPath: bin.appendingPathComponent("plain").path, contents: Data())
        try FileManager.default.createSymbolicLink(atPath: bin.appendingPathComponent("container").path, withDestinationPath: "../Cellar/container/1.6.0/bin/container")
        XCTAssertTrue(ReleaseVersion.managedByHomebrew(bin.appendingPathComponent("container").path))
        XCTAssertFalse(ReleaseVersion.managedByHomebrew(bin.appendingPathComponent("plain").path))
        // Apple's package replaces only /usr/local/bin/container; a copy elsewhere stays as it is.
        XCTAssertTrue(ReleaseVersion.installedByPackage("/usr/local/bin/container") && ReleaseVersion.installedByPackage("/usr/local/bin/../bin/container"))
        XCTAssertFalse(ReleaseVersion.installedByPackage("/opt/homebrew/bin/container") || ReleaseVersion.installedByPackage(bin.appendingPathComponent("plain").path))
        // Homebrew can lag a release; its formula says what `brew upgrade` would install.
        XCTAssertEqual(ReleaseVersion.homebrewStable(#"{"formulae":[{"name":"container","versions":{"stable":"1.5.0","head":null,"bottle":true}}],"casks":[]}"#), "1.5.0")
        XCTAssertNil(ReleaseVersion.homebrewStable(#"{"formulae":[],"casks":[]}"#)); XCTAssertNil(ReleaseVersion.homebrewStable("Error: No available formula"))
        XCTAssertTrue(ReleaseVersion.isMajorUpgrade("2.0.0", from: "1.6.0") && ReleaseVersion.isMajorUpgrade("1.0.0", from: "0.12.1"))
        XCTAssertFalse(ReleaseVersion.isMajorUpgrade("1.7.0", from: "1.6.0") || ReleaseVersion.isMajorUpgrade("1.6.0", from: "1.6.0"))
        // The last release found survives a relaunch, so the card does not wait a day to come back.
        let release = #"{"tag_name":"1.6.0","assets":[{"name":"container-1.6.0-installer-signed.pkg","size":42,"browser_download_url":"https://github.com/apple/container/releases/download/1.6.0/container-1.6.0-installer-signed.pkg"}]}"#
        let package = try XCTUnwrap(InstallerPackage.parse(release: Data(release.utf8)))
        XCTAssertEqual(try JSONDecoder().decode(InstallerPackage.self, from: try JSONEncoder().encode(package)), package)
        // Image names given by the user (tag, commit) never end in a separator.
        XCTAssertTrue(ImageReference.isNewName("registry.example.com:5000/team/app:1.0"))
        XCTAssertFalse(ImageReference.isNewName("team/app:") || ImageReference.isNewName("team/") || ImageReference.isNewName("app@sha256:abc"))
    }
    func testShellQuoteRoundTrip() async throws {
        let input = "a ' quote \" $HOME `false` $(false)\nsecond line"
        let result = try await Runner.checked(Command("/bin/sh", ["-c", "printf %s " + Command.quote(input)]))
        XCTAssertEqual(result, input)
        XCTAssertEqual(Command.quote("nginx:alpine"), "nginx:alpine")
        XCTAssertEqual(Command.quote(""), "''")
        XCTAssertEqual(Command.quote("=ls"), "'=ls'")
        XCTAssertEqual(Command("/usr/local/bin/container", ["run", "--env", "A=hello world"]).display, "/usr/local/bin/container run --env 'A=hello world'")
    }
    func testInstallerPackageComesFromOfficialReleases() {
        func asset(_ owner: String, _ name: String, scheme: String = "https", size: Int = 1) -> String {
            #"{"name":"\#(name)","browser_download_url":"\#(scheme)://github.com/\#(owner)/container/releases/download/1.5.0/\#(name)","size":\#(size)}"#
        }
        func release(_ assets: [String]) -> Data { Data((#"{"tag_name":"1.5.0","assets":["# + assets.joined(separator: ",") + "]}").utf8) }
        let package = InstallerPackage.parse(release: release([
            asset("someone", "container-1.5.0-installer-signed.pkg"),
            asset("apple", "container-1.5.0-installer-unsigned.pkg"),
            asset("apple", "container-1.5.0-installer-signed.pkg", size: 42),
            asset("apple", "container-1.5.0.zip")]))
        XCTAssertEqual(package?.fileName, "container-1.5.0-installer-signed.pkg")
        XCTAssertEqual(package?.version, "1.5.0"); XCTAssertEqual(package?.size, 42)
        XCTAssertEqual(InstallerPackage.parse(release: release([asset("apple", "container-1.5.0-installer-unsigned.pkg")]))?.fileName, "container-1.5.0-installer-unsigned.pkg")
        XCTAssertNil(InstallerPackage.parse(release: release([asset("someone", "container.pkg")])))
        XCTAssertNil(InstallerPackage.parse(release: release([asset("apple", "container.pkg", scheme: "http")])))
        XCTAssertNil(InstallerPackage.parse(release: Data(#"{"message":"API rate limit exceeded"}"#.utf8)))
    }
    func testTerminalScriptQuotesEveryPart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("harbor it's \(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let line = TerminalScript.shellLine(Command("/bin/sh", ["-c", #"pwd; printf %s "$1""#, "sh", #"a "b" $HOME"#], directory: directory))
        XCTAssertEqual(try await Runner.checked(Command("/bin/sh", ["-c", line])), directory + "\n" + #"a "b" $HOME"#)
        XCTAssertTrue(TerminalScript.shellLine(Command("/bin/echo", ["x"]), admin: true).hasPrefix("sudo /bin/echo"))
        let script = TerminalScript.appleScript(Command("/bin/echo", [#"say "hi" \ there"#]))
        XCTAssertTrue(script.contains(#"do script "/bin/echo 'say \"hi\" \\ there'""#))
    }
    func testLargeStdoutAndStderrDoNotDeadlock() async throws {
        let result = try await Runner.run(Command("/bin/sh", ["-c", "i=0; while [ $i -lt 15000 ]; do echo stdout-data; echo stderr-data >&2; i=$((i+1)); done"]), timeout: 10)
        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.output.count, 100_000)
        XCTAssertGreaterThan(result.errorOutput.count, 100_000)
    }
    func testOutputStreamsWhileRunning() async throws {
        let chunks = Chunks()
        let result = try await Runner.run(Command("/bin/sh", ["-c", "echo first; sleep 0.6; printf second"]), timeout: 10) { chunks.append($0) }
        XCTAssertEqual(chunks.all.joined(), "first\nsecond")
        XCTAssertGreaterThan(chunks.all.count, 1)
        XCTAssertEqual(result.output, "first\nsecond")
    }
    func testOversizedOutputStopsEarly() async throws {
        let start = Date()
        do { _ = try await Runner.run(Command("/bin/sh", ["-c", "while :; do echo harbor-harbor-harbor-harbor-harbor-harbor; done"]), timeout: 60); XCTFail("must stop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("2 MB")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 30)
    }
    func testOutputLimitCanBeRaised() async throws {
        do { _ = try await Runner.run(Command("/bin/sh", ["-c", "head -c 4096 /dev/zero"]), timeout: 10, outputLimit: 1024); XCTFail("must stop") }
        catch { XCTAssertTrue(error.localizedDescription.contains("1 KB")) }
        let result = try await Runner.run(Command("/bin/sh", ["-c", "head -c 3000000 /dev/zero"]), timeout: 20, outputLimit: 8 * 1_048_576)
        XCTAssertEqual(result.status, 0)
    }
    func testNonzeroExitIsReported() async throws {
        do { _ = try await Runner.checked(Command("/bin/sh", ["-c", "echo backend-error >&2; exit 7"])); XCTFail("must throw") }
        catch { XCTAssertTrue(error.localizedDescription.contains("backend-error")) }
    }
    func testTimeoutTerminatesProcess() async throws {
        let start = Date()
        do { _ = try await Runner.checked(Command("/bin/sleep", ["10"]), timeout: 0.15); XCTFail("must time out") }
        catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testCancellationTerminatesProcess() async throws {
        let start = Date()
        let task = Task { try await Runner.checked(Command("/bin/sleep", ["10"])) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; XCTFail("must cancel") }
        catch { XCTAssertTrue(error.localizedDescription.contains("canceled")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}

final class Chunks: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ chunk: String) { lock.lock(); items.append(chunk); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

// A dependency-free test runner also works with Command Line Tools (no Xcode/XCTest required).
func XCTFail(_ message: String) { fatalError(message) }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw HarborError.message("Unexpected nil") }; return value }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Values differ") }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T) { precondition(a > b) }
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T) { precondition(a < b) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression(); fatalError("Expected an error") } catch { }
}
@main struct HarborChecks {
    static func main() async throws {
        let suite = HarborCoreTests()
        try suite.testNativeManagedContainerAndLegacyState()
        try suite.testNativeImagesPreserveRegistryPort()
        suite.testImageReferencesKeepPortsAndDigests()
        suite.testNativeBackendDoesNotUseDocker()
        try suite.testTokenizerDoesNotEvaluateShell()
        suite.testNativeCatalogIncludesAllFeatureGroups()
        suite.testNativeHelpRejectsFallbackRootHelp()
        suite.testDockerAlwaysTargetsExplicitSocket()
        suite.testComposePreservesOverrideOrderAndWorkingDirectory()
        suite.testComposeDirectoryFollowsFileOrder()
        try suite.testDockerJSONLinesAndArray()
        try suite.testRunArgumentsKeepEnvironmentLiteral()
        try suite.testNativeDetailsAndStatsFrom150()
        try suite.testRunFormOptionalFlags()
        try suite.testBuildNetworkAndVolumeForms()
        suite.testComposeActionsTargetServices()
        try suite.testContainerFilesAndDockerImport()
        suite.testTextTablesAndResourceHelpers()
        try suite.testContainerFeaturesFrom160()
        try suite.testKubernetesClusters()
        try suite.testReleaseVersions()
        try await suite.testShellQuoteRoundTrip()
        suite.testInstallerPackageComesFromOfficialReleases()
        try await suite.testTerminalScriptQuotesEveryPart()
        try await suite.testLargeStdoutAndStderrDoNotDeadlock()
        try await suite.testOutputStreamsWhileRunning()
        try await suite.testOversizedOutputStopsEarly()
        try await suite.testOutputLimitCanBeRaised()
        try await suite.testNonzeroExitIsReported()
        try await suite.testTimeoutTerminatesProcess()
        try await suite.testCancellationTerminatesProcess()
        print("PASS: 31 checks — native JSON, registry ports, image references, native isolation, tokenizer, command catalog, scoped help, Docker socket isolation, Compose paths, Compose file order, JSON, literal arguments, 1.5.0 details and stats, run form flags, build/network/volume forms, Compose services, container files and Docker import, text tables, 1.6.0 aliases, partial image lists and commit, Kubernetes clusters, release versions, shell quoting, installer source, Terminal script, large output, streaming output, output limit, raised output limit, errors, timeout, cancellation")
    }
}
