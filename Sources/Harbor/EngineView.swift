import SwiftUI
import HarborCore

/// Shown on the Containers and Images pages until the engine runs.
struct EngineSetupView: View {
    @Environment(Store.self) private var store
    var body: some View {
        if store.engine == .checking {
            ProgressView("Connecting to Apple Container…").huggingGlassPanel(height: 200)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Up Apple Container").font(.system(size: 20, weight: .bold))
                    Text("Harbor drives Apple's official container runtime. Install it and start the engine; Harbor connects on its own.")
                        .foregroundStyle(Color.harborSub)
                }
                SetupGuide()
            }
            .card(padding: 28)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .paneScroll()
        }
    }
}

enum SetupStepState { case pending, current, working, done }

/// Install, start, run: each step shows what is done, what is happening, and the one thing to do next.
struct SetupGuide: View {
    @Environment(Store.self) private var store
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !HostInfo.isAppleSilicon {
                Label("Apple Container runs only on Macs with Apple silicon.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            SetupStep(number: 1, title: "Install Apple Container", state: installState) {
                switch installState {
                case .done: Text(store.config.container).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                case .working: progress(of: store.installJob)
                case .current, .pending: installOptions
                }
            }
            SetupStep(number: 2, title: "Start the engine", state: startState) {
                switch startState {
                case .done:
                    Text("Running.").foregroundStyle(.secondary)
                case .working:
                    progress(of: store.jobs.first { ($0.subject == "engine" || $0.subject == Store.installSubject) && $0.isRunning })
                    Text("The first start downloads the recommended Linux kernel, which can take a few minutes.").font(.caption).foregroundStyle(.secondary)
                case .current:
                    failure(of: store.jobs.first { $0.subject == "engine" }, prefix: "The last start failed")
                    if case .stopped(let reason) = store.engine {
                        Text(reason).font(.caption).foregroundStyle(.tertiary).lineLimit(3).textSelection(.enabled)
                    }
                    Button("Start Engine") { store.startEngine() }.buttonStyle(.borderedProminent)
                case .pending:
                    Text("Starts by itself once the installation finishes.").font(.callout).foregroundStyle(.secondary)
                }
            }
            SetupStep(number: 3, title: "Run your first container", state: readyState) {
                if readyState == .pending {
                    Text("Available once the engine runs.").font(.callout).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Run Container…") { store.present(.run(RunOptions())) }.buttonStyle(.borderedProminent)
                        Button("Pull Image…") { store.present(.pull) }
                    }
                }
            }
        }
        .animation(.smooth, value: store.engine)
        .animation(.smooth, value: installState)
        .animation(.smooth, value: startState)
    }

    private var installState: SetupStepState {
        if store.engine.isInstalled { return .done }
        return store.isBusy(Store.installSubject) ? .working : .current
    }
    private var startState: SetupStepState {
        if store.engine.isRunning { return .done }
        if store.isBusy("engine") || (store.engine.isInstalled && store.isBusy(Store.installSubject)) { return .working }
        return store.engine.isInstalled ? .current : .pending
    }
    private var readyState: SetupStepState {
        guard store.engine.isRunning else { return .pending }
        return store.containers.isEmpty ? .current : .done
    }

    @ViewBuilder private var installOptions: some View {
        failure(of: store.installJob, prefix: "The last attempt failed")
        HStack(spacing: 10) {
            if store.homebrew != nil {
                Button("Install with Homebrew") { store.installWithHomebrew() }.buttonStyle(.borderedProminent)
                Button("Download Official Installer") { store.installWithOfficialInstaller() }
            } else {
                Button("Download Official Installer") { store.installWithOfficialInstaller() }.buttonStyle(.borderedProminent)
            }
            Menu("Other Options") {
                if store.homebrew != nil { Button("Install with Homebrew in Terminal") { store.installWithHomebrewInTerminal() } }
                Link("Open the Releases Page", destination: InstallerPackage.releasesPage)
                Button("Use an Existing CLI…") { openSettings() }
            }
            .fixedSize()
        }
        .disabled(!HostInfo.isAppleSilicon)
        Text(store.homebrew != nil
             ? "Homebrew installs it without a password. Harbor then starts the engine for you."
             : "The installer asks for your administrator password in macOS Installer; Harbor never sees it. Harbor then starts the engine for you.")
            .font(.caption).foregroundStyle(.secondary)
    }
    @ViewBuilder private func progress(of job: Job?) -> some View {
        if let job {
            Text(Self.lastLine(of: job.output) ?? "Working…").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Button("Show Output") { store.present(.output(job)) }
                Button("Cancel") { job.cancel() }
            }
            .controlSize(.small)
        }
    }
    @ViewBuilder private func failure(of job: Job?, prefix: String) -> some View {
        if let job, job.status == .failed {
            HStack(alignment: .firstTextBaseline) {
                Label(prefix + ": " + (Self.lastLine(of: job.output) ?? "see the output"), systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red).lineLimit(2)
                Button("Show Output") { store.present(.output(job)) }.controlSize(.small)
            }
            .font(.callout)
        }
    }
    private static func lastLine(of text: String) -> String? {
        text.split(whereSeparator: \.isNewline).last { !$0.allSatisfy(\.isWhitespace) }.map { String($0) }
    }
}

private struct SetupStep<Content: View>: View {
    let number: Int
    let title: String
    let state: SetupStepState
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(badgeFill).frame(width: 28, height: 28)
                switch state {
                case .done: Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                case .working: ProgressView().controlSize(.small)
                case .current, .pending: Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(state == .current ? Color.white : Color.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline).foregroundStyle(state == .pending ? Color.secondary : Color.primary)
                content
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .opacity(state == .pending ? 0.75 : 1)
    }
    private var badgeFill: Color { switch state {
    case .done, .current: .harbor
    case .working: Color.harbor.opacity(0.15)
    case .pending: Color.secondary.opacity(0.15)
    } }
}

struct EngineView: View {
    @Environment(Store.self) private var store
    @ViewState<Bool> private var confirmStop = false
    @ViewState<InstallerPackage?> private var pendingUpdate: InstallerPackage?
    var body: some View {
        let busy = store.isBusy("engine")
        PageScaffold(title: "Engine", subtitle: "Apple Container" + (store.installedVersion.map { " " + $0 } ?? "")) {
            GlassControls {
                HeaderMenu(systemName: "ellipsis", help: "All system commands") { NativeActionItems(group: "System") }
                SettingsLink { HeaderIcon(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("Tool paths and appearance").accessibilityLabel("Settings")
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    RowIcon(systemName: "cpu", active: store.engine.isRunning).symbolEffect(.pulse, isActive: busy)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline).font(.system(size: 15, weight: .bold)).contentTransition(.opacity)
                        Text(store.config.container).font(.system(size: 11).monospaced()).foregroundStyle(Color.harborSub).textSelection(.enabled)
                    }
                    Spacer()
                    if store.engine.isRunning {
                        Button("Stop Engine…") { confirmStop = true }.buttonStyle(MiniButtonStyle()).disabled(busy)
                    } else if case .stopped = store.engine {
                        Button(busy ? "Starting…" : "Start Engine") { store.startEngine() }.buttonStyle(.borderedProminent).disabled(busy)
                    }
                }
                .card()
                if let update = store.availableUpdate { UpdateCard(update: update, busy: busy) { pendingUpdate = update } }
                // The guide is for getting started; once the engine runs and has run something, it steps aside.
                if !setUp {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Setup").font(.system(size: 13, weight: .semibold))
                        SetupGuide()
                    }
                    .card()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("System").font(.system(size: 13, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(NativeOperation.operations(in: "System").filter { Self.everyday.contains($0.id) }) { OperationTile(operation: $0) }
                    }
                    Text("The other system commands, such as kernels, DNS domains and properties, are in the … menu above. Quitting Harbor leaves the engine and your containers running.")
                        .font(.caption).foregroundStyle(Color.harborSub)
                }
                .card()
            }
            .animation(.smooth, value: store.engine)
            .paneScroll()
        }
        .confirmationDialog("Stop Apple Container?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop Engine", role: .destructive) { store.stopEngine() }
        } message: { Text("All running containers stop with it.") }
        .confirmationDialog("Update Apple Container to \(pendingUpdate?.version ?? "")?", isPresented: Binding(get: { pendingUpdate != nil }, set: { if !$0 { pendingUpdate = nil } }),
                            titleVisibility: .visible, presenting: pendingUpdate) { update in
            Button("Update", role: .destructive) { store.updateEngine(to: update) }
        } message: { _ in
            Text(store.engine.isRunning ? "The engine stops for the update, and every running container with it; it starts again afterwards. Containers do not restart on their own." : "The engine stays stopped afterwards.")
        }
    }
    /// Installed, running, and something has run: nothing left to set up.
    private var setUp: Bool { store.engine.isRunning && !store.containers.isEmpty }
    /// System commands for everyday checks; the rest stay in the page's menu.
    private static let everyday: Set<String> = ["system status", "system logs", "system df", "system version"]
    private var headline: String { switch store.engine {
    case .checking: "Connecting…"; case .missingCLI: "Apple Container is not installed"
    case .stopped: "Engine stopped"; case .running: "Engine running"
    } }
}

/// A newer Apple Container release than the installed one, with what updating does and how.
private struct UpdateCard: View {
    @Environment(Store.self) private var store
    let update: InstallerPackage
    let busy: Bool
    let start: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RowIcon(systemName: "arrow.down.circle")
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Container \(update.version) is available").font(.system(size: 13, weight: .semibold))
                Text("You have \(store.installedVersion ?? "an older version"). " + (ReleaseVersion.managedByHomebrew(store.config.container)
                     ? "Harbor updates it with Homebrew (brew upgrade container)."
                     : "Harbor downloads Apple's signed installer; macOS Installer asks for your password, Harbor never sees it."))
                    .font(.system(size: 11)).foregroundStyle(Color.harborSub).fixedSize(horizontal: false, vertical: true)
                Link("Release notes", destination: ReleaseVersion.notes(update.version)).font(.system(size: 11, weight: .medium))
            }
            Spacer(minLength: 0)
            Button(busy ? "Updating…" : "Update…", action: start).buttonStyle(.borderedProminent).disabled(busy)
        }
        .card()
    }
}

/// Edits a draft so half-typed paths never reach the running app; Apply or closing the window commits it.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Backdrop.self) private var backdrop
    @ViewState<RuntimeConfig?> private var draft: RuntimeConfig?
    @AppStorage(Preference.menuBarExtra) private var showMenuBarExtra = true
    @AppStorage(Preference.notifications) private var notify = true
    @AppStorage(Preference.updateCheck) private var checkUpdates = true
    @AppStorage(Preference.glassStyle) private var glassStyle = GlassStyle.clear.rawValue
    var body: some View {
        let edited = Binding(get: { draft ?? store.config }, set: { draft = $0 })
        Form {
            Section {
                Picker("Background", selection: Binding(get: { backdrop.style }, set: { backdrop.select($0) })) {
                    ForEach(BackdropStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                if backdrop.style == .custom {
                    LabeledContent("Picture") {
                        HStack {
                            Text(backdrop.picturePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Button("Choose…") { backdrop.choosePicture() }
                        }
                    }
                }
                Picker("Panels", selection: $glassStyle) {
                    ForEach(GlassStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } header: { Text("Appearance") } footer: {
                Text("Glass needs color and shape behind it, so Harbor draws its own background: soft aurora blocks, the harbor from the design, your desktop picture lined up with the screen, or a picture you choose. Clear panes barely blur it under bright edges and a slanted sheen; crystal panes frost it more, under a whiter tint. Floating controls are always clear Liquid Glass, and with Reduce Transparency on, the panes are solid.")
            }
            Section {
                Toggle("Show Harbor in the menu bar", isOn: $showMenuBarExtra)
                Toggle("Notify when a job finishes in the background", isOn: $notify)
                Toggle("Check for new Apple Container releases", isOn: $checkUpdates)
            } header: { Text("General") } footer: {
                Text("The menu bar shows the engine and running containers even when the window is closed. Notifications cover jobs that fail or take longer than a few seconds. The release check asks GitHub once a day; nothing is installed until you choose Update on the Engine page.")
            }
            Group {
                Section {
                    PathField(title: "container CLI", path: edited.container)
                } header: { Text("Apple Container") } footer: { Text("Every native action runs this executable directly, never through a shell.") }
                Section {
                    PathField(title: "Docker CLI", path: edited.docker)
                    PathField(title: "Socktainer", path: edited.socktainer)
                    TextField("Socket", text: edited.socket).font(.callout.monospaced())
                } header: { Text("Docker and Compose (optional)") } footer: {
                    Text("Docker commands always use this socket explicitly, and inherited Docker context variables are cleared.")
                }
                Section {
                    HStack {
                        Button("Detect Automatically") { draft = RuntimeConfig(socket: edited.wrappedValue.socket) }
                        Spacer()
                        Button("Apply", action: apply).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                            .disabled(draft == nil || draft == store.config)
                    }
                } footer: {
                    if store.bridgeOwned { Text("Stop the compatibility service before changing paths.") }
                }
            }
            .disabled(store.bridgeOwned)
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 700)
        .onDisappear(perform: apply)
    }
    private func apply() {
        if let draft { store.applySettings(draft) }
        draft = nil
    }
}

private struct PathField: View {
    let title: String
    @Binding var path: String
    var body: some View {
        let found = FileManager.default.isExecutableFile(atPath: path)
        LabeledContent {
            HStack {
                TextField(title, text: $path).labelsHidden().font(.callout.monospaced())
                Image(systemName: found ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(found ? Color.harborLive : .orange)
                    .help(found ? "Found" : "No executable at this path")
            }
        } label: { Text(title) }
    }
}
