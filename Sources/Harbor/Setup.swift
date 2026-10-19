import SwiftUI
import AppKit
import HarborCore

enum HostInfo {
    /// Apple Container needs Apple silicon. Reads the hardware, so it is also right under Rosetta.
    static let isAppleSilicon: Bool = {
        var value: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }()
}

/// Installing Apple Container. Every route ends the same way: find the CLI, adopt its path and start the
/// engine. Passwords are only ever typed into macOS (Installer or Terminal), never into Harbor.
extension Store {
    static let installSubject = "install"
    var homebrew: String? { RuntimeConfig.locate("brew") }
    var installJob: Job? { jobs.first { $0.subject == Self.installSubject } }

    /// `brew install container` inside Harbor, with its output in the job.
    func installWithHomebrew() {
        guard let brew = homebrew else { return }
        run("Install Apple Container", subject: Self.installSubject) { [self] job in
            job.note("Installing with Homebrew: brew install container")
            var environment = RuntimeConfig.toolEnvironment
            environment["HOMEBREW_NO_ENV_HINTS"] = "1"; environment["HOMEBREW_NO_COLOR"] = "1"
            try await stream(Command(brew, ["install", "container"], environment: environment), into: job, timeout: 3600)
            try await startInstalledEngine(job)
        }
    }
    /// The same Homebrew install in Terminal, for setups where it asks for a password.
    func installWithHomebrewInTerminal() {
        guard let brew = homebrew else { return }
        run("Install Apple Container", subject: Self.installSubject) { [self] job in
            try await stream(Command("/usr/bin/osascript", ["-e", TerminalScript.appleScript(Command(brew, ["install", "container"]))]), into: job, timeout: 30)
            job.note("Finish the installation in Terminal. Harbor continues on its own.")
            try await startInstalledEngine(job, waitingForInstaller: true)
        }
    }
    /// Apple's signed package from the official GitHub release: downloaded to Downloads and marked as a
    /// download (so Gatekeeper checks it), its signature checked, then opened in Installer.
    func installWithOfficialInstaller() {
        run("Install Apple Container", subject: Self.installSubject) { [self] job in
            job.note("Looking up the latest Apple Container release…")
            var request = URLRequest(url: InstallerPackage.latestRelease)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.expectSuccess(response, from: "GitHub")
            guard let package = InstallerPackage.parse(release: data) else {
                throw HarborError.message("The latest release has no installer package. Open the releases page to download one yourself.")
            }
            job.note("Downloading \(package.fileName) (\(ByteCountFormatter.string(fromByteCount: package.size, countStyle: .file)))…")
            let (download, downloadResponse) = try await URLSession.shared.download(from: package.url)
            try Self.expectSuccess(downloadResponse, from: "GitHub's download server")
            let destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent(package.fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: download, to: destination)
            try Self.markAsDownloaded(destination, from: package.url)
            job.note("Saved to \(destination.path). Checking its signature…")
            try await stream(Command("/usr/sbin/pkgutil", ["--check-signature", destination.path]), into: job, timeout: 60)
            job.note("Opening Installer. macOS asks for your administrator password there; Harbor never sees it.")
            try await stream(Command("/usr/bin/open", [destination.path]), into: job, timeout: 30)
            try await startInstalledEngine(job, waitingForInstaller: true)
        }
    }
    private func startInstalledEngine(_ job: Job, waitingForInstaller: Bool = false) async throws {
        var path = RuntimeConfig.locate("container")
        if waitingForInstaller && path == nil {
            job.note("Waiting for the installation to finish…")
            var waited = 0
            while path == nil && waited < 1800 { try await Task.sleep(for: .seconds(2)); waited += 2; path = RuntimeConfig.locate("container") }
        }
        guard let path else {
            throw HarborError.message("No container CLI was found in \(RuntimeConfig.toolDirectories.joined(separator: ", ")). If it is installed elsewhere, set its path in Settings.")
        }
        adoptCLI(path)
        job.note("Found \(path). Starting the engine; the first start downloads the recommended Linux kernel…")
        try await stream(config.nativeCommand(["system", "start", "--enable-kernel-install"]), into: job, timeout: 900)
        job.note("Apple Container is running.")
    }
    private static func expectSuccess(_ response: URLResponse, from source: String) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, status != 200 else { return }
        throw HarborError.message("\(source) answered HTTP \(status). Try again later, or open the releases page.")
    }
    /// Marks a file the way browsers mark downloads, so Gatekeeper assesses it before it opens.
    private static func markAsDownloaded(_ file: URL, from source: URL) throws {
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineAgentNameKey as String: "Harbor",
            kLSQuarantineDataURLKey as String: source.absoluteString]
        var file = file
        try file.setResourceValues(values)
    }
}
