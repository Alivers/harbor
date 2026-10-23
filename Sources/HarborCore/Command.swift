import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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
    /// POSIX single quoting; words made only of safe characters stay bare so copied commands read naturally.
    public static func quote(_ s: String) -> String {
        if !s.isEmpty, s.first != "=", s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
    // A leading "=" is quoted anyway because zsh expands `=name` to a command path.
    private static let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@+=:,./_-")
}

/// The only shell path: a command typed into Terminal.app, with every argument and the working directory quoted separately.
public enum TerminalScript {
    public static func shellLine(_ command: Command, admin: Bool = false) -> String {
        (command.directory.map { "cd " + Command.quote($0) + " && " } ?? "") + (admin ? "sudo " : "") + command.display
    }
    public static func appleScript(_ command: Command, admin: Bool = false) -> String {
        let line = shellLine(command, admin: admin).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application \"Terminal\"\nactivate\ndo script \"\(line)\"\nend tell"
    }
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
    /// Default per-stream output cap; anything larger belongs in Terminal.
    public static let outputLimit: UInt64 = 2 * 1024 * 1024

    // Separate temporary files drain both streams without pipe-buffer deadlocks.
    // Commands run off the main thread; timeout/cancellation terminates this process only, and so does
    // output beyond `outputLimit`, so a chatty command cannot fill the disk before it exits.
    // `onOutput` receives new complete lines about every 250 ms while the command runs, then the unterminated rest.
    // A stream the caller consumes as it arrives (followed logs) can pass a larger `outputLimit`.
    public static func run(_ command: Command, timeout: TimeInterval = 30, outputLimit: UInt64 = Runner.outputLimit,
                           onOutput: (@Sendable (String) -> Void)? = nil) async throws -> CommandResult {
        let tooLarge = tooLargeMessage(outputLimit)
        let job = Task.detached(priority: .userInitiated) { () throws -> CommandResult in
            let fm = FileManager.default
            guard fm.isExecutableFile(atPath: command.executable) else {
                throw HarborError.message("Executable not found: \(command.executable)\nInstall the tool, or fix its path in Settings.")
            }
            let dir = fm.temporaryDirectory.appendingPathComponent("harbor-" + UUID().uuidString)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }
            let out = try Capture(dir.appendingPathComponent("stdout")), err = try Capture(dir.appendingPathComponent("stderr"))
            defer { out.close(); err.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments; process.environment = command.environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = out.writer; process.standardError = err.writer
            if let directory = command.directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
            try process.run()
            func stop(_ reason: String) throws -> Never {
                process.terminate()
                for _ in 0..<10 where process.isRunning { usleep(50_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                // Polled rather than waitUntilExit, which on macOS 27 can block forever in this thread's run loop.
                while process.isRunning { usleep(10_000) }
                throw HarborError.message(reason)
            }
            func publish(final: Bool) throws {
                guard let onOutput else { return }
                let text = try out.newText(final: final) + err.newText(final: final)
                if !text.isEmpty { onOutput(text) }
            }
            let deadline = Date().addingTimeInterval(timeout)
            var nextPublish = Date()
            while process.isRunning {
                if Task.isCancelled { try stop("Operation canceled. The backend task may still be running; refresh to check its state.") }
                if Date() > deadline { try stop("Command timed out (\(Int(timeout))s). The backend task may still be running; refresh to check its state.") }
                if try max(out.size(), err.size()) > outputLimit { try stop(tooLarge) }
                if Date() >= nextPublish { try publish(final: false); nextPublish = Date().addingTimeInterval(0.25) }
                try? await Task.sleep(for: .milliseconds(50))
            }
            if try max(out.size(), err.size()) > outputLimit { throw HarborError.message(tooLarge) }
            try publish(final: true)
            return try CommandResult(output: out.text(), errorOutput: err.text(), status: process.terminationStatus)
        }
        return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
    }
    public static func checked(_ command: Command, timeout: TimeInterval = 30) async throws -> String {
        let result = try await run(command, timeout: timeout)
        guard result.status == 0 else { throw HarborError.message(result.combined.isEmpty ? "Command failed with exit code \(result.status)" : result.combined) }
        return result.output
    }
    static func tooLargeMessage(_ limit: UInt64) -> String {
        let size = limit >= 1_048_576 ? "\(limit / 1_048_576) MB" : "\(limit / 1024) KB"
        return "Command output exceeds \(size); view it in Terminal."
    }
}

/// One captured output stream: the child process writes the file, the runner reads it back.
private final class Capture {
    let writer: FileHandle
    private let reader: FileHandle
    private var published: UInt64 = 0
    init(_ url: URL) throws {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        writer = try FileHandle(forWritingTo: url); reader = try FileHandle(forReadingFrom: url)
    }
    func size() throws -> UInt64 { try reader.seekToEnd() }
    /// Text written since the previous call, cut after the last line break unless `final`.
    /// Line breaks are ASCII, so the cut never splits a UTF-8 sequence.
    func newText(final: Bool) throws -> String {
        try reader.seek(toOffset: published)
        let data = try reader.readToEnd() ?? Data()
        let end = final ? data.endIndex : (data.lastIndex(where: { $0 == 0x0A || $0 == 0x0D }).map { $0 + 1 } ?? data.startIndex)
        published += UInt64(end - data.startIndex)
        return String(decoding: data[data.startIndex..<end], as: UTF8.self)
    }
    func text() throws -> String {
        try reader.seek(toOffset: 0)
        return String(decoding: try reader.readToEnd() ?? Data(), as: UTF8.self)
    }
    func close() { try? writer.close(); try? reader.close() }
}

public struct RuntimeConfig: Codable, Equatable, Sendable {
    /// Where Homebrew and the official installers put the tools, in lookup order.
    public static let toolDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
    /// PATH for child processes; an app launched from Finder inherits only a minimal one.
    static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    /// The socket Socktainer listens on when started without options; the built-in launcher only supports this one.
    public static let defaultSocket = NSHomeDirectory() + "/.socktainer/container.sock"
    public var docker: String
    public var container: String
    public var socktainer: String
    public var socket: String
    public init(docker: String = Self.find("docker"), container: String = Self.find("container"),
                socktainer: String = Self.find("socktainer"), socket: String = Self.defaultSocket) {
        self.docker = docker; self.container = container; self.socktainer = socktainer; self.socket = socket
    }
    public static func find(_ name: String) -> String { locate(name) ?? toolDirectories[0] + "/" + name }
    /// The first executable named `name` in `toolDirectories`, if any.
    public static func locate(_ name: String) -> String? {
        toolDirectories.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    /// Environment for tools Harbor runs directly (container, brew): inherited, with a full PATH.
    public static var toolEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        return env
    }
    public var environment: [String: String] { environment(socket: socket) }
    func environment(socket: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // An inherited context/TLS setting must never redirect a Harbor command to OrbStack.
        for key in ["DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH", "DOCKER_API_VERSION", "COMPOSE_FILE", "COMPOSE_PROJECT_NAME", "COMPOSE_PROFILES"] { env.removeValue(forKey: key) }
        env["PATH"] = Self.searchPath
        env["DOCKER_HOST"] = "unix://" + socket
        env["COMPOSE_ANSI"] = "never"
        return env
    }
    public func dockerCommand(_ args: [String], directory: String? = nil) -> Command {
        Command(docker, ["--host", "unix://" + socket] + args, directory: directory, environment: environment)
    }
    /// A Docker command against another engine (an import source), named by its socket just as explicitly.
    public func dockerCommand(_ args: [String], socket other: String) -> Command {
        Command(docker, ["--host", "unix://" + other] + args, environment: environment(socket: other))
    }
    public func nativeCommand(_ args: [String]) -> Command { Command(container, args, environment: Self.toolEnvironment) }
    public func composeCommand(_ project: ComposeProject, _ args: [String]) -> Command {
        dockerCommand(["compose", "--ansi", "never", "--project-directory", project.directory] + project.files.flatMap { ["--file", $0] } + args, directory: project.directory)
    }
}
