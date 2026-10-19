import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HarborCore

/// What Harbor knows about the native engine.
enum EngineState: Equatable {
    case checking, missingCLI, stopped(String), running
    var isRunning: Bool { self == .running }
    var isInstalled: Bool { switch self { case .stopped, .running: true; case .checking, .missingCLI: false } }
}

/// A catalog command opened in the command sheet, with the arguments to start from.
struct NativeRequest: Identifiable {
    let operation: NativeOperation
    let arguments: String
    init(_ operation: NativeOperation, arguments: String? = nil) { self.operation = operation; self.arguments = arguments ?? operation.example }
    var id: String { operation.id + "|" + arguments }
}

/// The window's one sheet; `Store.present` swaps sheets without overlapping them.
enum SheetRoute: Identifiable {
    case run(RunOptions), pull, operation(NativeRequest), output(Job)
    var id: String { switch self {
    case .run: "run"
    case .pull: "pull"
    case .operation(let request): "operation " + request.id
    case .output(let job): "output " + job.id.uuidString
    } }
}

/// One user-triggered command (or short sequence of commands) and its output.
@MainActor @Observable final class Job: Identifiable {
    enum Status { case running, succeeded, failed, canceled }
    let id = UUID()
    let title: String
    /// The resource this job changes; other actions on it wait until the job finishes.
    let subject: String?
    let started = Date()
    var status = Status.running
    var output = ""
    @ObservationIgnored var task: Task<Void, Never>?
    init(title: String, subject: String?) { self.title = title; self.subject = subject }
    var isRunning: Bool { status == .running }
    func cancel() { task?.cancel() }
    /// Appends a line of Harbor's own, as opposed to command output.
    func note(_ line: String) { output += (output.isEmpty || output.hasSuffix("\n") ? "" : "\n") + line + "\n" }
}

@MainActor @Observable final class Store {
    var config: RuntimeConfig
    var projects: [ComposeProject]
    private(set) var engine = EngineState.checking
    private(set) var containers: [ContainerRow] = []
    private(set) var images: [ImageRow] = []
    private(set) var imageError: String?
    /// Containers of each Compose project; only read while the Docker API is reachable.
    private(set) var services: [ComposeProject.ID: Result<[ContainerRow], Error>] = [:]
    private(set) var dockerConnected = false
    private(set) var bridgeOwned = false
    /// Newest first. Jobs run concurrently; only jobs on the same `subject` exclude each other.
    private(set) var jobs: [Job] = []
    /// Bumped whenever a job finishes, so views showing raw CLI listings know to read them again.
    private(set) var changeCount = 0
    /// The finished job the activity capsule reports.
    var banner: Job?
    var sheet: SheetRoute?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var helpCache: [String: String] = [:]
    @ObservationIgnored private var bridge: Process?
    @ObservationIgnored private var bridgeLog: FileHandle?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    private var bridgeLogURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harbor/bridge.log")
    }

    init() {
        config = UserDefaults.standard.data(forKey: "runtime").flatMap { try? JSONDecoder().decode(RuntimeConfig.self, from: $0) } ?? RuntimeConfig()
        projects = UserDefaults.standard.data(forKey: "projects").flatMap { try? JSONDecoder().decode([ComposeProject].self, from: $0) } ?? []
        // The window may already be closed at quit time, so the store itself stops the Socktainer it started.
        // No queue: AppKit posts this on the main thread and the block must finish before the app exits.
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.jobs.forEach { $0.cancel() }; self?.stopOwnedBridge() }
        }
    }
    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(config), forKey: "runtime")
        UserDefaults.standard.set(try? JSONEncoder().encode(projects), forKey: "projects")
    }
    /// Applies edited settings: persists them, forgets cached help and reconnects.
    func applySettings(_ edited: RuntimeConfig) {
        guard edited != config else { return }
        config = edited; save(); helpCache = [:]
        Task { await refresh(); await refreshCompatibility() }
    }

    // MARK: Native state

    /// Polls while Harbor is the active app; the root view owns this task.
    func poll() async {
        while !Task.isCancelled {
            if NSApplication.shared.isActive { await refresh() }
            try? await Task.sleep(for: .seconds(6))
        }
    }
    func refresh() async {
        // A request during a read may predate a change that read cannot see, so run one more pass.
        guard !refreshing else { refreshQueued = true; return }
        refreshing = true; defer { refreshing = false }
        repeat { refreshQueued = false; await readNativeState() } while refreshQueued
    }
    private func readNativeState() async {
        // Picks up a CLI installed since launch, or by a different method than the configured path assumes.
        if !FileManager.default.isExecutableFile(atPath: config.container), let found = RuntimeConfig.locate("container") { adoptCLI(found) }
        let snapshot = config
        guard FileManager.default.isExecutableFile(atPath: snapshot.container) else { return apply(.missingCLI, snapshot) }
        do {
            let rows = try NativeParser.containers(try await Runner.checked(snapshot.nativeCommand(["list", "--all", "--format", "json"]), timeout: 10))
            var imageRows: [ImageRow] = [], imageFailure: String?
            do { imageRows = try NativeParser.images(try await Runner.checked(snapshot.nativeCommand(["image", "list", "--format", "json"]), timeout: 10)) }
            catch { imageFailure = error.localizedDescription }
            apply(.running, snapshot, containers: rows, images: imageRows, imageError: imageFailure)
        } catch {
            apply(.stopped(error.localizedDescription), snapshot)
        }
    }
    /// Publishes a read unless the settings changed meanwhile. Unchanged values are not reassigned,
    /// so the 6-second poll does not redraw views that have nothing new to show.
    private func apply(_ state: EngineState, _ snapshot: RuntimeConfig, containers rows: [ContainerRow] = [], images imageRows: [ImageRow] = [], imageError failure: String? = nil) {
        guard config == snapshot else { return }
        if engine != state { engine = state }
        if containers != rows { containers = rows }
        if images != imageRows { images = imageRows }
        if imageError != failure { imageError = failure }
    }
    /// Points Harbor at a newly found CLI.
    func adoptCLI(_ path: String) {
        guard config.container != path else { return }
        config.container = path; save(); helpCache = [:]
    }
    func read(_ arguments: [String], timeout: TimeInterval = 20) async throws -> String {
        try await Runner.checked(config.nativeCommand(arguments), timeout: timeout)
    }
    /// The local help for a subcommand, cached per CLI path; nil when the CLI does not know the command.
    func help(for path: [String]) async -> String? {
        let key = config.container + " " + path.joined(separator: " ")
        if let cached = helpCache[key] { return cached }
        guard let text = try? await read(path + ["--help"], timeout: 10), NativeHelp.matches(text, path: path) else { return nil }
        helpCache[key] = text
        return text
    }
    /// Features are gated on the local CLI's help, never on a version number.
    func supports(_ path: [String], flag: String) async -> Bool { await help(for: path)?.contains(flag) ?? false }

    // MARK: Jobs

    var runningJobs: [Job] { jobs.filter { $0.isRunning } }
    func isBusy(_ subject: String) -> Bool { jobs.contains { $0.subject == subject && $0.isRunning } }

    /// The one path for user-triggered work. The job runs in the background; its output is kept for the
    /// Activity list and shown in a sheet right away only when `showOutput` (logs, reports, raw commands).
    @discardableResult
    func run(_ title: String, subject: String? = nil, showOutput: Bool = false, _ work: @escaping @MainActor (Job) async throws -> Void) -> Job? {
        if let subject, isBusy(subject) { return nil }
        let job = Job(title: title, subject: subject)
        jobs.insert(job, at: 0)
        if jobs.count > 40 { jobs.removeLast(jobs.count - 40) }
        if showOutput { present(.output(job)) }
        job.task = Task { [self] in
            do { try await work(job); if job.output.isEmpty { job.output = "Done." }; job.status = .succeeded }
            catch {
                let canceled = Task.isCancelled
                job.note(error is CancellationError ? "Canceled." : error.localizedDescription)
                job.status = canceled ? .canceled : .failed
            }
            finished(job, showOutput: showOutput)
            await refresh(); await refreshServices()
        }
        return job
    }
    @discardableResult
    func perform(_ title: String, command: Command, subject: String? = nil, showOutput: Bool = false, timeout: TimeInterval = 120) -> Job? {
        run(title, subject: subject, showOutput: showOutput) { [self] job in try await stream(command, into: job, timeout: timeout) }
    }
    /// Runs `command` inside a job, appending its output as it arrives; a nonzero exit fails the job.
    func stream(_ command: Command, into job: Job, timeout: TimeInterval) async throws {
        let (chunks, sink) = AsyncStream.makeStream(of: String.self)
        let reader = Task { for await chunk in chunks { job.output += chunk } }
        let result: CommandResult
        do { result = try await Runner.run(command, timeout: timeout) { sink.yield($0) } }
        catch { sink.finish(); await reader.value; throw error }
        sink.finish(); await reader.value
        guard result.status == 0 else { throw HarborError.message("Exited with code \(result.status).") }
    }
    private func finished(_ job: Job, showOutput: Bool) {
        changeCount += 1
        switch job.status {
        case .failed: banner = job
        case .succeeded where !(showOutput && isShowing(job)):
            banner = job
            Task { try? await Task.sleep(for: .seconds(4)); if banner === job { banner = nil } }
        default: break
        }
    }
    func clearFinishedJobs() { jobs.removeAll { !$0.isRunning }; banner = nil }

    // MARK: Sheets

    func present(_ route: SheetRoute) {
        guard sheet != nil else { sheet = route; return }
        // macOS shows one sheet at a time: let the current one finish closing first.
        sheet = nil
        Task { try? await Task.sleep(for: .milliseconds(350)); sheet = route }
    }
    private func isShowing(_ job: Job) -> Bool {
        if case .output(let shown)? = sheet { return shown === job }
        return false
    }

    // MARK: Engine, containers and images

    func startEngine() { perform("Start engine", command: config.nativeCommand(["system", "start", "--enable-kernel-install"]), subject: "engine", timeout: 600) }
    func stopEngine() { perform("Stop engine", command: config.nativeCommand(["system", "stop"]), subject: "engine", timeout: 300) }
    func start(_ container: ContainerRow) { perform("Start \(container.name)", command: config.nativeCommand(["start", container.id]), subject: container.id) }
    func stop(_ container: ContainerRow) { perform("Stop \(container.name)", command: config.nativeCommand(["stop", container.id]), subject: container.id) }
    func restart(_ container: ContainerRow) {
        let snapshot = config
        run("Restart \(container.name)", subject: container.id) { [self] job in
            try await stream(snapshot.nativeCommand(["stop", container.id]), into: job, timeout: 120)
            try await stream(snapshot.nativeCommand(["start", container.id]), into: job, timeout: 120)
        }
    }
    /// Deletes a container, stopping it first when it is running.
    func delete(_ container: ContainerRow) {
        let snapshot = config
        run("Delete \(container.name)", subject: container.id) { [self] job in
            if container.running { try await stream(snapshot.nativeCommand(["stop", container.id]), into: job, timeout: 120) }
            try await stream(snapshot.nativeCommand(["delete", container.id]), into: job, timeout: 120)
        }
    }
    func runContainer(_ options: RunOptions) throws {
        let arguments = try options.arguments()
        perform("Run \(options.image.trimmingCharacters(in: .whitespaces))", command: config.nativeCommand(arguments), timeout: 1800)
    }
    func pull(_ reference: String) { perform("Pull \(reference)", command: config.nativeCommand(["image", "pull", reference]), subject: "image " + reference, timeout: 1800) }
    func delete(_ image: ImageRow) { perform("Delete \(image.reference)", command: config.nativeCommand(["image", "delete", image.reference]), subject: "image " + image.reference) }

    // MARK: Optional Docker compatibility

    func startBridge() {
        guard !bridgeOwned else { return }
        let snapshot = config
        run("Start compatibility service", subject: "bridge") { [self] job in
            guard snapshot.socket == RuntimeConfig.defaultSocket else {
                throw HarborError.message("The built-in launcher uses the default Socktainer socket. Start the service yourself for a custom socket.")
            }
            job.note("Starting Apple Container…")
            try await stream(snapshot.nativeCommand(["system", "start", "--enable-kernel-install"]), into: job, timeout: 600)
            let help = try await Runner.checked(Command(snapshot.socktainer, ["--help"], environment: snapshot.environment))
            guard help.contains("--no-docker-context") else { throw HarborError.message("This Socktainer version lacks --no-docker-context. Upgrade it before using the built-in launcher.") }
            // Adopt an already running service without spawning another daemon.
            let alreadyRunning = await dockerReachable(snapshot, timeout: 5)
            if !alreadyRunning {
                job.note("Starting Socktainer…")
                try launchBridge(snapshot)
                do { try await waitForBridge(snapshot) } catch { stopOwnedBridge(); throw error }
            }
            dockerConnected = true; job.note("The optional Docker API is ready.")
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
        let reachable = await dockerReachable(config, timeout: 5)
        if dockerConnected != reachable { dockerConnected = reachable }
        await refreshServices()
    }
    /// The Socktainer log as a finished job, so it opens in the same output sheet as everything else.
    func showBridgeLog() {
        run("Socktainer service log", showOutput: true) { [self] job in
            guard let handle = try? FileHandle(forReadingFrom: bridgeLogURL) else { job.note("No service log yet."); return }
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            try handle.seek(toOffset: size > 256_000 ? size - 256_000 : 0)
            job.output = String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
        }
    }
    func diagnostics() {
        let snapshot = config
        run("Diagnostics", showOutput: true) { job in
            let commands: [(String, Command)] = [
                ("Apple Container", snapshot.nativeCommand(["--version"])),
                ("Socktainer", Command(snapshot.socktainer, ["--version"], environment: snapshot.environment)),
                ("Docker CLI", snapshot.dockerCommand(["--version"])),
                ("Compose", snapshot.dockerCommand(["compose", "version"])),
                ("Docker API", snapshot.dockerCommand(["version"]))]
            for (name, command) in commands {
                try Task.checkCancellation()
                do { let result = try await Runner.run(command, timeout: 10); job.note("\(name) [exit \(result.status)]\n\(result.combined)\n") }
                catch { job.note("\(name)\n\(error.localizedDescription)\n") }
            }
        }
    }
    func createDockerContext() {
        perform("Create harbor-apple context", command: config.dockerCommand(["context", "create", "harbor-apple", "--docker", "host=unix://" + config.socket]))
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
    func moveFile(_ project: ComposeProject, from index: Int, by offset: Int) {
        guard let p = projects.firstIndex(where: { $0.id == project.id }), projects[p].files.indices.contains(index + offset) else { return }
        projects[p].files.swapAt(index, index + offset); save()
    }
    func compose(_ project: ComposeProject, _ action: ComposeAction) {
        let snapshot = config
        run("\(project.name): \(action.rawValue)", subject: project.id.uuidString, showOutput: action.showsOutput) { [self] job in
            if action == .start {
                // Fail fast on a broken file before anything is pulled or created.
                job.note("Validating Compose configuration…")
                _ = try await Runner.checked(snapshot.composeCommand(project, ComposeAction.validate.arguments), timeout: 30)
                job.note("Configuration is valid. Starting; the first image pull can take a few minutes…")
            }
            try await stream(snapshot.composeCommand(project, action.arguments), into: job, timeout: 1200)
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

    // MARK: Terminal, Finder and clipboard

    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    func openShell(_ container: ContainerRow) {
        openInTerminal(config.nativeCommand(["exec", "--interactive", "--tty", container.id, "/bin/sh"]), title: "Open shell in \(container.name)")
    }
    /// The only shell path; `TerminalScript` quotes every argument and the working directory.
    func openInTerminal(_ command: Command, admin: Bool = false, title: String = "Open in Terminal") {
        perform(title, command: Command("/usr/bin/osascript", ["-e", TerminalScript.appleScript(command, admin: admin)]))
    }
}

extension ComposeAction {
    /// Reports open in the output sheet; lifecycle actions report in the activity capsule.
    var showsOutput: Bool { self == .logs || self == .status || self == .validate }
}
