import Foundation
import HarborCore

final class HarborCoreTests {
    func testNativeManagedContainerAndLegacyState() throws {
        let row = #"{"configuration":{"id":"web","image":{"reference":"nginx:alpine"},"resources":{"cpus":2,"memoryInBytes":1073741824},"publishedPorts":[{"hostPort":8080,"containerPort":80}]},"status":{"state":"running","networks":[]}}"#
        let containers = try NativeParser.containers("[" + row + "]")
        XCTAssertEqual(containers[0].Names, "web")
        XCTAssertTrue(containers[0].running)
        XCTAssertTrue(containers[0].Ports.contains("8080"))
        let legacy = #"[{"configuration":{"id":"web","image":{"reference":"nginx:alpine"}},"status":"stopped"}]"#
        XCTAssertEqual(try NativeParser.containers(legacy)[0].State, "stopped")
        XCTAssertThrowsError(try NativeParser.containers("[{}]"))
    }
    func testNativeImagesPreserveRegistryPort() throws {
        let input = #"[{"configuration":{"name":"localhost:5000/team/app:dev","descriptor":{"digest":"sha256:abc"}},"variants":[{"size":1024}]}]"#
        let image = try NativeParser.images(input)[0]
        XCTAssertEqual(image.reference, "localhost:5000/team/app:dev")
        XCTAssertEqual(image.identifier, "sha256:abc")
        XCTAssertThrowsError(try NativeParser.images("{}"))
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
        XCTAssertThrowsError(try ArgumentTokenizer.split("'unclosed"))
        XCTAssertThrowsError(try ArgumentTokenizer.split("trailing\\"))
    }
    func testNativeCatalogIncludesAllFeatureGroups() {
        let groups = Set(NativeOperation.all.map(\.group))
        XCTAssertEqual(groups, Set(["Containers", "Images", "Build", "Networks", "Volumes", "Registries", "Linux Machines", "System", "Kubernetes"]))
        XCTAssertEqual(Set(NativeOperation.all.map(\.id)).count, NativeOperation.all.count)
    }
    func testNativeHelpRejectsFallbackRootHelp() {
        XCTAssertTrue(NativeHelp.matches("USAGE: container volume create [options]", path: ["volume", "create"]))
        XCTAssertTrue(NativeHelp.matches("USAGE: k8s create [options]", path: ["k8s", "create"]))
        XCTAssertEqual(NativeHelp.matches("USAGE: container [--debug] <subcommand>", path: ["volume", "create"]), false)
    }
    func testDockerAlwaysTargetsExplicitSocket() {
        let config = RuntimeConfig(docker: "/bin/docker", container: "/bin/container", socktainer: "/bin/socktainer", socket: "/tmp/harbor socket")
        let command = config.dockerCommand(["ps", "--all"])
        XCTAssertEqual(command.arguments, ["--host", "unix:///tmp/harbor socket", "ps", "--all"])
        XCTAssertNil(command.environment["DOCKER_CONTEXT"])
        XCTAssertNil(command.environment["DOCKER_TLS_VERIFY"])
        XCTAssertEqual(command.environment["DOCKER_HOST"], "unix:///tmp/harbor socket")
    }
    func testComposePreservesOverrideOrderAndWorkingDirectory() {
        let files = ["/tmp/project with spaces/compose.yaml", "/tmp/project with spaces/dev.override.yaml"]
        let project = ComposeProject(files: files)
        let command = RuntimeConfig().composeCommand(project, ["up", "--detach"])
        XCTAssertEqual(command.directory, "/tmp/project with spaces")
        XCTAssertEqual(Array(command.arguments.suffix(6)), ["--file", files[0], "--file", files[1], "up", "--detach"])
        XCTAssertTrue(command.arguments.contains("--project-directory"))
    }
    func testDockerJSONLinesAndArray() throws {
        let row = #"{"ID":"abc","Names":"web","Image":"nginx:alpine","State":"running","Status":"Up 4 minutes","Ports":"127.0.0.1:8080->80/tcp"}"#
        let lines = try JSONRows.decode(ContainerRow.self, from: row + "\n" + row)
        XCTAssertEqual(lines.count, 2); XCTAssertTrue(lines[0].running)
        XCTAssertEqual(try JSONRows.decode(ContainerRow.self, from: "[" + row + "]").count, 1)
        XCTAssertEqual(try JSONRows.decode(ContainerRow.self, from: "\n").count, 0)
        XCTAssertThrowsError(try JSONRows.decode(ContainerRow.self, from: "backend failed"))
    }
    func testRunArgumentsKeepEnvironmentLiteral() throws {
        var options = RunOptions(); options.environment = "TOKEN=$(touch /tmp/should-never-exist)\nGREETING=hello world"
        let args = try options.arguments()
        XCTAssertTrue(args.contains("TOKEN=$(touch /tmp/should-never-exist)"))
        XCTAssertTrue(args.contains("GREETING=hello world"))
        XCTAssertEqual(args.last, "nginx:alpine")
        options.image = "--privileged"; XCTAssertThrowsError(try options.arguments())
        options.image = "nginx"; options.environment = "invalid"; XCTAssertThrowsError(try options.arguments())
    }
    func testShellQuoteRoundTrip() async throws {
        let input = "a ' quote \" $HOME `false` $(false)\nsecond line"
        let result = try await Runner.checked(Command("/bin/sh", ["-c", "printf %s " + Command.quote(input)]))
        XCTAssertEqual(result, input)
    }
    func testLargeStdoutAndStderrDoNotDeadlock() async throws {
        let result = try await Runner.run(Command("/bin/sh", ["-c", "i=0; while [ $i -lt 15000 ]; do echo stdout-data; echo stderr-data >&2; i=$((i+1)); done"]), timeout: 10)
        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.output.count, 100_000)
        XCTAssertGreaterThan(result.errorOutput.count, 100_000)
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

// A dependency-free test runner also works with Command Line Tools (no Xcode/XCTest required).
func XCTFail(_ message: String) { fatalError(message) }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
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
        suite.testNativeBackendDoesNotUseDocker()
        try suite.testTokenizerDoesNotEvaluateShell()
        suite.testNativeCatalogIncludesAllFeatureGroups()
        suite.testNativeHelpRejectsFallbackRootHelp()
        suite.testDockerAlwaysTargetsExplicitSocket()
        suite.testComposePreservesOverrideOrderAndWorkingDirectory()
        try suite.testDockerJSONLinesAndArray()
        try suite.testRunArgumentsKeepEnvironmentLiteral()
        try await suite.testShellQuoteRoundTrip()
        try await suite.testLargeStdoutAndStderrDoNotDeadlock()
        try await suite.testNonzeroExitIsReported()
        try await suite.testTimeoutTerminatesProcess()
        try await suite.testCancellationTerminatesProcess()
        print("PASS: 15 checks — native JSON, registry ports, native isolation, tokenizer, command catalog, scoped help, Docker socket isolation, Compose paths, JSON, literal arguments, shell quoting, large output, errors, timeout, cancellation")
    }
}
