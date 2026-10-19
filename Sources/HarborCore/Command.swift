import Foundation
import Darwin

public struct Command: Sendable {
    public var executable: String
    public var arguments: [String]
    public var directory: String?
    public var environment: [String: String]
    public init(_ executable: String, _ arguments: [String], directory: String? = nil,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executable = executable; self.arguments = arguments
        self.directory = directory; self.environment = environment
    }
    public var display: String { ([executable] + arguments).map(Self.quote).joined(separator: " ") }
    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
}

public struct CommandResult: Sendable {
    public let output: String
    public let errorOutput: String
    public let status: Int32
    public var combined: String { [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n") }
}

public enum HarborError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

public enum Runner {
    // Separate temporary files drain both streams without pipe-buffer deadlocks.
    // Commands run off the main thread; timeout/cancellation terminates this process only.
    public static func run(_ command: Command, timeout: TimeInterval = 30) async throws -> CommandResult {
        let job = Task.detached(priority: .userInitiated) { () throws -> CommandResult in
            let fm = FileManager.default
            guard fm.isExecutableFile(atPath: command.executable) else {
                throw HarborError.message("Executable not found: \(command.executable)\nInstall the tool, or fix its path in Settings.")
            }
            let dir = fm.temporaryDirectory.appendingPathComponent("harbor-" + UUID().uuidString)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }
            let out = dir.appendingPathComponent("stdout"), err = dir.appendingPathComponent("stderr")
            fm.createFile(atPath: out.path, contents: nil); fm.createFile(atPath: err.path, contents: nil)
            let oh = try FileHandle(forWritingTo: out), eh = try FileHandle(forWritingTo: err)
            defer { try? oh.close(); try? eh.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments; process.environment = command.environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = oh; process.standardError = eh
            if let directory = command.directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Task.isCancelled || Date() > deadline {
                    process.terminate()
                    for _ in 0..<10 where process.isRunning { usleep(50_000) }
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    process.waitUntilExit()
                    throw HarborError.message(Task.isCancelled ? "Operation canceled. The backend task may still be running; refresh to check its state." : "Command timed out (\(Int(timeout))s). The backend task may still be running; refresh to check its state.")
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            process.waitUntilExit()
            func read(_ url: URL) throws -> String {
                let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                let size = try file.seekToEnd(), limit: UInt64 = 2 * 1024 * 1024
                if size > limit { throw HarborError.message("Command output exceeds 2 MB; view it in Terminal.") }
                try file.seek(toOffset: 0)
                return String(decoding: try file.readToEnd() ?? Data(), as: UTF8.self)
            }
            return try CommandResult(output: read(out), errorOutput: read(err), status: process.terminationStatus)
        }
        return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
    }
    public static func checked(_ command: Command, timeout: TimeInterval = 30) async throws -> String {
        let result = try await run(command, timeout: timeout)
        guard result.status == 0 else { throw HarborError.message(result.combined.isEmpty ? "Command failed with exit code \(result.status)" : result.combined) }
        return result.output
    }
}

public struct RuntimeConfig: Codable, Equatable, Sendable {
    public var docker: String
    public var container: String
    public var socktainer: String
    public var socket: String
    public init(docker: String = Self.find("docker"), container: String = Self.find("container"),
                socktainer: String = Self.find("socktainer"), socket: String = NSHomeDirectory() + "/.socktainer/container.sock") {
        self.docker = docker; self.container = container; self.socktainer = socktainer; self.socket = socket
    }
    public static func find(_ name: String) -> String {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return paths.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/" + name
    }
    public var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        // An inherited context/TLS setting must never redirect a Harbor command to OrbStack.
        for key in ["DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH", "DOCKER_API_VERSION", "COMPOSE_FILE", "COMPOSE_PROJECT_NAME", "COMPOSE_PROFILES"] { env.removeValue(forKey: key) }
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["DOCKER_HOST"] = "unix://" + socket
        env["COMPOSE_ANSI"] = "never"
        return env
    }
    public func dockerCommand(_ args: [String], directory: String? = nil) -> Command {
        Command(docker, ["--host", "unix://" + socket] + args, directory: directory, environment: environment)
    }
    public func nativeCommand(_ args: [String]) -> Command {
        var nativeEnvironment = ProcessInfo.processInfo.environment
        nativeEnvironment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return Command(container, args, environment: nativeEnvironment)
    }
    public func composeCommand(_ project: ComposeProject, _ args: [String]) -> Command {
        dockerCommand(["compose", "--ansi", "never", "--project-directory", project.directory] + project.files.flatMap { ["--file", $0] } + args, directory: project.directory)
    }
}
