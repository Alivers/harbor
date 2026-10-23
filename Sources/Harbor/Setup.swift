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
            try await openInInstaller(try await Self.latestPackage(), job: job)
            try await startInstalledEngine(job, waitingForInstaller: true)
        }
    }
    /// The signed package of the newest release on GitHub.
    private static func latestPackage() async throws -> InstallerPackage {
        var request = URLRequest(url: InstallerPackage.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try expectSuccess(response, from: "GitHub")
        guard let package = InstallerPackage.parse(release: data) else {
            throw HarborError.message("The latest release has no installer package. Open the releases page to download one yourself.")
        }
        return package
    }
    /// Downloads the package to Downloads, checks its signature and opens it in Installer.
    private func openInInstaller(_ package: InstallerPackage, job: Job) async throws {
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

    // MARK: Updates

    /// A newer release than the installed CLI, if the last check found one.
    var availableUpdate: InstallerPackage? {
        guard Preference.enabled(Preference.updateCheck), let latest = latestRelease, let installed = installedVersion,
              ReleaseVersion.isNewer(latest.version, than: installed) else { return nil }
        return latest
    }
    /// Asks GitHub for the latest release at most once a day, and only while the check is on. Failures are quiet:
    /// the next day's check tries again.
    func checkForUpdate() async {
        guard Preference.enabled(Preference.updateCheck), Date().timeIntervalSince(lastUpdateCheck) >= 86_400 else { return }
        lastUpdateCheck = Date()
        UserDefaults.standard.set(lastUpdateCheck, forKey: Preference.lastUpdateCheck)
        guard let package = try? await Self.latestPackage(), latestRelease != package else { return }
        latestRelease = package
        UserDefaults.standard.set(try? JSONEncoder().encode(package), forKey: Preference.latestRelease)
    }
    /// Turning the check off hides what it found at once; turning it on checks at the next poll.
    func updateCheckChanged(_ enabled: Bool) {
        lastUpdateCheck = .distantPast
        UserDefaults.standard.removeObject(forKey: Preference.lastUpdateCheck)
        if !enabled { latestRelease = nil; UserDefaults.standard.removeObject(forKey: Preference.latestRelease) }
    }
    /// Stops the engine, installs the new release the way the CLI was installed (Homebrew or Apple's package), and
    /// starts the engine again. Containers stop with the engine; the caller confirms that first. Nothing is stopped
    /// when the update cannot replace the CLI Harbor uses.
    func updateEngine(to package: InstallerPackage) {
        let snapshot = config, wasRunning = engine.isRunning
        let brew = ReleaseVersion.managedByHomebrew(snapshot.container) ? homebrew : nil
        run("Update Apple Container to \(package.version)", subject: "engine") { [self] job in
            var environment = RuntimeConfig.toolEnvironment
            environment["HOMEBREW_NO_ENV_HINTS"] = "1"; environment["HOMEBREW_NO_COLOR"] = "1"
            if let brew {
                // The formula can lag the GitHub release by days, and then brew upgrade would do nothing.
                job.note("Asking Homebrew which version it offers…")
                try await stream(Command(brew, ["update"], environment: environment), into: job, timeout: 600)
                let offered = ReleaseVersion.homebrewStable(try await Runner.checked(Command(brew, ["info", "--json=v2", "container"], environment: environment), timeout: 120))
                guard let offered, !ReleaseVersion.isNewer(package.version, than: offered) else {
                    throw HarborError.message("Homebrew does not offer Apple Container \(package.version) yet" + (offered.map { "; it has \($0)" } ?? "")
                                              + ". Nothing was stopped. Try again once Homebrew's formula is updated.")
                }
                environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            } else if ReleaseVersion.managedByHomebrew(snapshot.container) {
                throw HarborError.message("This Apple Container came from Homebrew, but brew was not found. Run brew upgrade container in Terminal.")
            } else if !ReleaseVersion.installedByPackage(snapshot.container) {
                throw HarborError.message("Apple's installer replaces \(ReleaseVersion.packagePath), not the copy Harbor uses at \(snapshot.container). Update that copy yourself, or choose \(ReleaseVersion.packagePath) in Settings.")
            }
            if wasRunning {
                job.note("Stopping the engine…")
                try await stream(snapshot.nativeCommand(["system", "stop"]), into: job, timeout: 300)
            }
            do {
                if let brew {
                    job.note("Updating with Homebrew: brew upgrade container")
                    try await stream(Command(brew, ["upgrade", "container"], environment: environment), into: job, timeout: 3600)
                } else {
                    try await openInInstaller(package, job: job)
                    job.note("Waiting for the installation to finish…")
                    try await waitForVersion(package.version, of: snapshot)
                }
            } catch {
                // Leave the engine as it was found, unless the person canceled.
                if wasRunning && !Task.isCancelled {
                    job.note(error.localizedDescription + "\nStarting the engine again…")
                    try? await stream(snapshot.nativeCommand(["system", "start"]), into: job, timeout: 900)
                }
                throw error
            }
            await refreshVersion()
            if wasRunning {
                job.note("Starting the engine…")
                try await stream(snapshot.nativeCommand(["system", "start", "--enable-kernel-install"]), into: job, timeout: 900)
            }
            guard let version = installedVersion, !ReleaseVersion.isNewer(package.version, than: version) else {
                throw HarborError.message("Apple Container is still \(installedVersion ?? "the old version"). If Homebrew does not offer \(package.version) yet, try again later or use the official installer.")
            }
            job.note("Apple Container \(version) is installed.")
        }
    }
    /// Waits up to half an hour for Installer to put the new CLI in place.
    private func waitForVersion(_ version: String, of snapshot: RuntimeConfig) async throws {
        for _ in 0..<600 {
            try await Task.sleep(for: .seconds(3))
            let output = try? await Runner.checked(snapshot.nativeCommand(["--version"]), timeout: 10)
            if let installed = output.flatMap(ReleaseVersion.cli), !ReleaseVersion.isNewer(version, than: installed) { return }
        }
        throw HarborError.message("Installer has not finished after half an hour. Finish it, then refresh.")
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
