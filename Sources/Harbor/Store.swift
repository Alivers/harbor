import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HarborCore

@MainActor final class Store: ObservableObject {
    @Published var config: RuntimeConfig
    @Published var projects: [ComposeProject]
    @Published var containers: [ContainerRow] = []
    @Published var images: [ImageRow] = []
    /// Containers of each Compose project; only read while the Docker API is reachable.
    @Published var services: [ComposeProject.ID: Result<[ContainerRow], Error>] = [:]
    @Published var connected = false
    @Published var dockerConnected = false
    @Published var connectionMessage = "Not connected yet"
    @Published var nativeOperation: NativeOperation?
    @Published var checking = false
    // Activity: the single user-triggered job and its output (see `run`).
    @Published var busy = false
    @Published var outputTitle = "Activity"
    @Published var output = ""
    @Published var outputFailed = false
    @Published var showOutput = false
    @Published var bridgeOwned = false
    private var bridge: Process?
    private var bridgeLog: FileHandle?
    private var activeTask: Task<Void, Never>?
    private var refreshQueued = false
    private var terminationObserver: NSObjectProtocol?
    private var bridgeLogURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harbor/bridge.log")
    }

    init() {
        config = UserDefaults.standard.data(forKey: "runtime").flatMap { try? JSONDecoder().decode(RuntimeConfig.self, from: $0) } ?? RuntimeConfig()
        projects = UserDefaults.standard.data(forKey: "projects").flatMap { try? JSONDecoder().decode([ComposeProject].self, from: $0) } ?? []
        // The window (and its views) may already be closed at quit time, so the store itself stops the Socktainer it started.
        // No queue: AppKit posts this on the main thread and the block must finish before the app exits.
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel(); self?.stopOwnedBridge() }
        }
    }
    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(config), forKey: "runtime")
        UserDefaults.standard.set(try? JSONEncoder().encode(projects), forKey: "projects")
    }

    // MARK: Native state

    func refresh() async {
        guard !busy else { return }
        // A request during a read may predate a change that read cannot see, so run one more pass.
        guard !checking else { refreshQueued = true; return }
        checking = true; defer { checking = false }
        repeat { refreshQueued = false; await readNativeState() } while refreshQueued && !busy
    }
    private func readNativeState() async {
        let snapshot = config
        do {
            let rows = try NativeParser.containers(try await Runner.checked(snapshot.nativeCommand(["list", "--all", "--format", "json"]), timeout: 10))
            var imageRows: [ImageRow] = [], message = "Connected to the native Apple Container engine"
            do { imageRows = try NativeParser.images(try await Runner.checked(snapshot.nativeCommand(["image", "list", "--format", "json"]), timeout: 10)) }
            catch { message = "Containers connected; failed to read images: \(error.localizedDescription)" }
            guard config == snapshot else { return }
            containers = rows; images = imageRows; connected = true; connectionMessage = message
        } catch {
            guard config == snapshot else { return }
            connected = false; containers = []; images = []
            connectionMessage = error.localizedDescription
        }
    }

    // MARK: Activity

    /// The one path for user-triggered work: one job at a time, output streamed into the Activity sheet,
    /// failures reported there as well (reopening it), then a refresh of native and Compose state.
    func run(_ title: String, _ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; outputTitle = title; output = ""; outputFailed = false; showOutput = true
        activeTask = Task { [self] in
            do { try await work(); if output.isEmpty { output = "Done." } }
            catch {
                let canceled = Task.isCancelled
                note(error is CancellationError ? "Operation canceled." : error.localizedDescription)
                if !canceled { outputFailed = true; showOutput = true }
            }
            busy = false; activeTask = nil
            await refresh(); await refreshServices()
        }
    }
    func perform(_ title: String, command: Command, timeout: TimeInterval = 60) {
        run(title) { [self] in try await stream(command, timeout: timeout) }
    }
    func cancel() { activeTask?.cancel() }
    /// Runs `command` inside a job, appending its output as it arrives; a nonzero exit fails the job.
    private func stream(_ command: Command, timeout: TimeInterval) async throws {
        let (chunks, sink) = AsyncStream.makeStream(of: String.self)
        let reader = Task { [self] in for await chunk in chunks { output += chunk } }
        let result: CommandResult
        do { result = try await Runner.run(command, timeout: timeout) { sink.yield($0) } }
        catch { sink.finish(); await reader.value; throw error }
        sink.finish(); await reader.value
        guard result.status == 0 else { throw HarborError.message("Exited with code \(result.status).") }
    }
    /// Appends a status line of the app's own to the Activity output.
    private func note(_ line: String) { output += (output.isEmpty || output.hasSuffix("\n") ? "" : "\n") + line + "\n" }

    // MARK: Optional Docker compatibility

    func startBridge() {
        guard !bridgeOwned else { return }
        let snapshot = config
        run("Start Apple Container and Compatibility Service") { [self] in
            guard snapshot.socket == RuntimeConfig.defaultSocket else {
                throw HarborError.message("The built-in launcher uses the default Socktainer socket. Start the service yourself for a custom socket.")
            }
            note("Starting Apple Container…")
            try await stream(snapshot.nativeCommand(["system", "start", "--enable-kernel-install"]), timeout: 300)
            let help = try await Runner.checked(Command(snapshot.socktainer, ["--help"], environment: snapshot.environment))
            guard help.contains("--no-docker-context") else { throw HarborError.message("This Socktainer version lacks --no-docker-context. Upgrade it before using the built-in launcher.") }
            // Adopt an already running service without spawning another daemon.
            let alreadyRunning = await dockerReachable(snapshot, timeout: 5)
            if !alreadyRunning {
                note("Starting Socktainer…")
                try launchBridge(snapshot)
                do { try await waitForBridge(snapshot) } catch { stopOwnedBridge(); throw error }
            }
            dockerConnected = true; note("The optional Docker API is ready. Import a Compose project to get started.")
        }
    }
    func stopOwnedBridge() {
        bridge?.terminate(); bridgeOwned = false
        dockerConnected = false
    }
    private func launchBridge(_ snapshot: RuntimeConfig) throws {
        try FileManager.default.createDirectory(at: bridgeLogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: bridgeLogURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: bridgeLogURL)
        let process = Process(); process.executableURL = URL(fileURLWithPath: snapshot.socktainer)
        process.arguments = ["--no-docker-context"]; process.environment = snapshot.environment
        process.standardInput = FileHandle.nullDevice; process.standardOutput = log; process.standardError = log
        process.terminationHandler = { [weak self] exited in
            let id = ObjectIdentifier(exited)
            Task { @MainActor in self?.bridgeExited(id) }
        }
        do { try process.run() } catch { try? log.close(); throw error }
        bridge = process; bridgeLog = log; bridgeOwned = true
    }
    private func bridgeExited(_ id: ObjectIdentifier) {
        guard let bridge, ObjectIdentifier(bridge) == id else { return }
        self.bridge = nil; try? bridgeLog?.close(); bridgeLog = nil
        bridgeOwned = false; dockerConnected = false
    }
    private func waitForBridge(_ snapshot: RuntimeConfig) async throws {
        for _ in 0..<30 {
            try Task.checkCancellation()
            guard bridge?.isRunning == true else { throw HarborError.message("Socktainer exited. Open the service log to check version compatibility.") }
            if await dockerReachable(snapshot, timeout: 2) { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw HarborError.message("The compatibility service is not ready yet. Check the service log, then refresh the connection.")
    }
    private func dockerReachable(_ snapshot: RuntimeConfig, timeout: TimeInterval) async -> Bool {
        (try? await Runner.run(snapshot.dockerCommand(["info"]), timeout: timeout))?.status == 0
    }
    func refreshCompatibility() async {
        dockerConnected = await dockerReachable(config, timeout: 5)
        await refreshServices()
    }
    func readBridgeLog() {
        guard !busy else { return }
        outputTitle = "Socktainer Service Log"; outputFailed = false
        if let handle = try? FileHandle(forReadingFrom: bridgeLogURL) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 256_000 ? size - 256_000 : 0)
            output = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        } else { output = "No service log yet." }
        showOutput = true
    }
    func diagnostics() {
        let snapshot = config
        run("Diagnostics") { [self] in
            let commands: [(String, Command)] = [
                ("Apple Container", snapshot.nativeCommand(["--version"])),
                ("Socktainer", Command(snapshot.socktainer, ["--version"], environment: snapshot.environment)),
                ("Docker CLI", snapshot.dockerCommand(["--version"])),
                ("Compose", snapshot.dockerCommand(["compose", "version"])),
                ("Docker API", snapshot.dockerCommand(["version"]))]
            for (name, command) in commands {
                try Task.checkCancellation()
                do { let result = try await Runner.run(command, timeout: 10); note("\(name) [\(result.status)]\n\(result.combined)\n") }
                catch { note("\(name)\n\(error.localizedDescription)\n") }
            }
        }
    }

    // MARK: Compose projects

    func importProject() {
        let panel = NSOpenPanel(); panel.title = "Choose Compose Files (override files can be selected too)"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.yaml]
        guard panel.runModal() == .OK else { return }
        let files = panel.urls.map(\.path)
        guard !files.isEmpty, !projects.contains(where: { $0.files == files }) else { return }
        projects.append(ComposeProject(files: files)); save()
        Task { await refreshServices() }
    }
    func removeProject(_ project: ComposeProject) { projects.removeAll { $0.id == project.id }; services[project.id] = nil; save() }
    /// Later files override earlier ones, so moving a file up lowers its precedence.
    func moveFileUp(_ project: ComposeProject, at index: Int) {
        guard index > 0, let p = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[p].files.swapAt(index, index - 1); save()
    }
    func compose(_ project: ComposeProject, _ action: ComposeAction) {
        let snapshot = config
        run("\(project.name) · \(action.rawValue)") { [self] in
            if action == .start {
                // Fail fast on a broken file before anything is pulled or created.
                note("Validating Compose configuration…")
                _ = try await Runner.checked(snapshot.composeCommand(project, ComposeAction.validate.arguments), timeout: 30)
                note("Configuration is valid. Starting; the first image pull can take a few minutes…")
            }
            try await stream(snapshot.composeCommand(project, action.arguments), timeout: 1200)
        }
    }
    func refreshServices() async {
        let snapshot = config
        var found: [ComposeProject.ID: Result<[ContainerRow], Error>] = [:]
        if dockerConnected {
            for project in projects {
                do {
                    let json = try await Runner.checked(snapshot.composeCommand(project, ComposeProject.serviceQuery), timeout: 15)
                    found[project.id] = .success(try JSONRows.decode(ContainerRow.self, from: json))
                } catch { found[project.id] = .failure(error) }
            }
        }
        guard config == snapshot else { return }
        services = found
    }

    // MARK: Terminal and clipboard

    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func openTerminal(_ container: ContainerRow) {
        openInTerminal(config.nativeCommand(["exec", "--interactive", "--tty", container.name, "/bin/sh"]))
    }
    /// The only shell path; `TerminalScript` quotes every argument and the working directory.
    func openInTerminal(_ command: Command, admin: Bool = false) {
        perform("Open in Terminal", command: Command("/usr/bin/osascript", ["-e", TerminalScript.appleScript(command, admin: admin)]))
    }
}
