import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HarborCore

@MainActor final class Store: ObservableObject {
    @Published var config: RuntimeConfig
    @Published var projects: [ComposeProject]
    @Published var containers: [ContainerRow] = []
    @Published var images: [ImageRow] = []
    @Published var connected = false
    @Published var dockerConnected = false
    @Published var nativeOperation: NativeOperation?
    @Published var checking = false
    @Published var busy = false
    @Published var operation = ""
    @Published var error: String?
    @Published var connectionMessage = "Not connected yet"
    @Published var output = "Operation results appear here."
    @Published var outputTitle = "Activity"
    @Published var showOutput = false
    @Published var bridgeOwned = false
    private var bridge: Process?
    private var bridgeLog: FileHandle?
    private var activeTask: Task<Void, Never>?
    private var bridgeLogURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harbor/bridge.log")
    }

    init() {
        config = UserDefaults.standard.data(forKey: "runtime").flatMap { try? JSONDecoder().decode(RuntimeConfig.self, from: $0) } ?? RuntimeConfig()
        projects = UserDefaults.standard.data(forKey: "projects").flatMap { try? JSONDecoder().decode([ComposeProject].self, from: $0) } ?? []
    }
    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(config), forKey: "runtime")
        UserDefaults.standard.set(try? JSONEncoder().encode(projects), forKey: "projects")
    }
    func refresh() async {
        guard !checking, !busy else { return }
        checking = true; defer { checking = false }
        let snapshot = config
        do {
            let result = try await Runner.checked(snapshot.nativeCommand(["list", "--all", "--format", "json"]), timeout: 10)
            let rows = try NativeParser.containers(result)
            guard config == snapshot else { return }
            containers = rows; connected = true; connectionMessage = "Connected to the native Apple Container engine"
            do {
                let text = try await Runner.checked(snapshot.nativeCommand(["image", "list", "--format", "json"]), timeout: 10)
                guard config == snapshot else { return }
                images = try NativeParser.images(text)
            } catch { images = []; connectionMessage = "Containers connected; failed to read images: \(error.localizedDescription)" }
        } catch {
            guard config == snapshot else { return }
            connected = false; containers = []; images = []
            connectionMessage = error.localizedDescription
        }
    }
    func perform(_ title: String, command: Command, timeout: TimeInterval = 60) {
        guard !busy else { return }
        busy = true; operation = title; outputTitle = title; output = "Running…"; showOutput = true
        activeTask = Task { [self] in
            do {
                let result = try await Runner.run(command, timeout: timeout)
                output = result.combined.isEmpty ? "Done." : result.combined
                if result.status != 0 { error = "\(title) failed (exit code \(result.status))\n\(result.combined)" }
            } catch { output = error.localizedDescription; self.error = error.localizedDescription }
            busy = false; activeTask = nil
            await refresh()
        }
    }
    func cancel() { activeTask?.cancel() }
    func startBridge() {
        guard !busy, !bridgeOwned else { return }
        let snapshot = config
        busy = true; operation = "Start Apple Container and Compatibility Service"; outputTitle = operation; output = "Checking services…"; showOutput = true
        activeTask = Task { [self] in
            do {
                guard snapshot.socket == NSHomeDirectory() + "/.socktainer/container.sock" else {
                    throw HarborError.message("The built-in launcher uses the default Socktainer socket. Start the service yourself for a custom socket.")
                }
                _ = try await Runner.checked(snapshot.nativeCommand(["system", "start", "--enable-kernel-install"]), timeout: 120)
                let help = try await Runner.checked(Command(snapshot.socktainer, ["--help"], environment: snapshot.environment))
                guard help.contains("--no-docker-context") else { throw HarborError.message("This Socktainer version lacks --no-docker-context. Upgrade it before using the built-in launcher.") }
                try Task.checkCancellation()
                // Adopt an already running service without spawning another daemon.
                let probe = try? await Runner.run(snapshot.dockerCommand(["info"]), timeout: 5)
                if probe?.status != 0 {
                    try FileManager.default.createDirectory(at: bridgeLogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    FileManager.default.createFile(atPath: bridgeLogURL.path, contents: nil)
                    let log = try FileHandle(forWritingTo: bridgeLogURL)
                    let process = Process(); process.executableURL = URL(fileURLWithPath: snapshot.socktainer)
                    process.arguments = ["--no-docker-context"]; process.environment = snapshot.environment
                    process.standardInput = FileHandle.nullDevice; process.standardOutput = log; process.standardError = log
                    process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.bridgeOwned = false; self?.bridge = nil; try? self?.bridgeLog?.close(); self?.bridgeLog = nil } }
                    try process.run(); bridge = process; bridgeLog = log; bridgeOwned = true
                    var ready = false
                    for _ in 0..<30 {
                        try Task.checkCancellation()
                        guard process.isRunning else { throw HarborError.message("Socktainer exited. Open the service log to check version compatibility.") }
                        if let result = try? await Runner.run(snapshot.dockerCommand(["info"]), timeout: 2), result.status == 0 { ready = true; break }
                        try await Task.sleep(for: .seconds(1))
                    }
                    guard ready else { throw HarborError.message("The compatibility service is not ready yet. Check the service log, then refresh the connection.") }
                }
                dockerConnected = true; output = "The optional Docker API is ready. Import a Compose project to get started."
            } catch { self.error = error.localizedDescription; output = error.localizedDescription }
            busy = false; activeTask = nil; await refresh()
        }
    }
    func stopOwnedBridge() {
        bridge?.terminate(); bridgeOwned = false
        dockerConnected = false
    }
    func readBridgeLog() {
        outputTitle = "Socktainer Service Log"
        if let handle = try? FileHandle(forReadingFrom: bridgeLogURL) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 256_000 ? size - 256_000 : 0)
            output = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        } else { output = "No service log yet." }
        showOutput = true
    }
    func importProject() {
        let panel = NSOpenPanel(); panel.title = "Choose Compose Files (override files can be selected too)"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.yaml]
        if panel.runModal() == .OK {
            let files = panel.urls.map(\.path)
            guard !files.isEmpty else { return }
            if !projects.contains(where: { $0.files == files }) { projects.append(ComposeProject(files: files)); save() }
        }
    }
    func removeProject(_ project: ComposeProject) { projects.removeAll { $0.id == project.id }; save() }
    func compose(_ project: ComposeProject, action: String) {
        guard !busy else { return }
        let args: [String]
        switch action {
        case "Validate": args = ["config", "--quiet"]
        case "Start": args = ["up", "--detach"]
        case "Stop": args = ["stop"]
        case "Logs": args = ["logs", "--no-color", "--tail", "300"]
        case "Status": args = ["ps", "--all"]
        case "Build": args = ["build"]
        default: return
        }
        if action != "Start" { perform("\(project.name) · \(action)", command: config.composeCommand(project, args), timeout: 1200); return }
        busy = true; operation = "\(project.name) · Start"; outputTitle = operation; output = "Validating Compose configuration…"; showOutput = true
        let snapshot = config
        activeTask = Task { [self] in
            do {
                _ = try await Runner.checked(snapshot.composeCommand(project, ["config", "--quiet"]), timeout: 30)
                output = "Configuration is valid. Starting; the first image pull can take a few minutes…"
                let result = try await Runner.run(snapshot.composeCommand(project, args), timeout: 1200)
                output = result.combined.isEmpty ? "Project started." : result.combined
                if result.status != 0 { throw HarborError.message(output) }
            } catch { self.error = error.localizedDescription; output = error.localizedDescription }
            busy = false; activeTask = nil; await refresh()
        }
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func openTerminal(_ container: ContainerRow) {
        openNativeTerminal(["exec", "--interactive", "--tty", container.Names, "/bin/sh"])
    }
    func openNativeTerminal(_ arguments: [String], directory: String? = nil, admin: Bool = false) {
        let command = (directory.map { "cd " + Command.quote($0) + " && " } ?? "") + (admin ? "sudo " : "") + config.nativeCommand(arguments).display
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        perform("Open Native Terminal", command: Command("/usr/bin/osascript", ["-e", script]))
    }
    func refreshCompatibility() async {
        let result = try? await Runner.run(config.dockerCommand(["info"]), timeout: 5)
        dockerConnected = result?.status == 0
    }
    func diagnostics() {
        guard !busy else { return }
        busy = true; operation = "Diagnostics"; outputTitle = operation; output = ""; showOutput = true
        let snapshot = config
        activeTask = Task { [self] in
            let commands: [(String, Command)] = [
                ("Apple Container", snapshot.nativeCommand(["--version"])),
                ("Socktainer", Command(snapshot.socktainer, ["--version"], environment: snapshot.environment)),
                ("Docker CLI", snapshot.dockerCommand(["--version"])),
                ("Compose", snapshot.dockerCommand(["compose", "version"])),
                ("Docker API", snapshot.dockerCommand(["version"]))]
            for (name, command) in commands {
                if Task.isCancelled { break }
                do { let result = try await Runner.run(command, timeout: 10); output += "\(name) [\(result.status)]\n\(result.combined)\n\n" }
                catch { output += "\(name)\n\(error.localizedDescription)\n\n" }
            }
            busy = false; activeTask = nil
        }
    }
}
