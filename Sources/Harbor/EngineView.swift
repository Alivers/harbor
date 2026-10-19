import SwiftUI
import HarborCore

/// Shown on the Containers and Images pages until the engine runs.
struct EngineSetupView: View {
    @Environment(Store.self) private var store
    var body: some View {
        if store.engine == .checking {
            ProgressView("Connecting to Apple Container…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set Up Apple Container").font(.title.weight(.semibold))
                        Text("Harbor drives Apple's official container runtime. Install it and start the engine; Harbor connects on its own.")
                            .foregroundStyle(.secondary)
                    }
                    SetupGuide()
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(32)
                .frame(maxWidth: .infinity)
            }
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
    var body: some View {
        let busy = store.isBusy("engine")
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "cpu").font(.system(size: 34, weight: .light)).foregroundStyle(store.engine.isRunning ? Color.harbor : .secondary)
                        .symbolEffect(.pulse, isActive: busy)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline).font(.title2.weight(.semibold)).contentTransition(.opacity)
                        Text(store.config.container).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    if store.engine.isRunning {
                        Button("Stop Engine…") { confirmStop = true }.disabled(busy)
                    } else if case .stopped = store.engine {
                        Button(busy ? "Starting…" : "Start Engine") { store.startEngine() }.buttonStyle(.borderedProminent).disabled(busy)
                    }
                }
                .card()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Setup").font(.headline)
                    SetupGuide()
                }
                .card()
                VStack(alignment: .leading, spacing: 10) {
                    Text("System").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(NativeOperation.operations(in: "System")) { OperationTile(operation: $0) }
                    }
                }
                .card()
                Text("Quitting Harbor leaves the engine and your containers running. Features follow the local CLI's help, so newer versions add actions without a Harbor update.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .animation(.smooth, value: store.engine)
        }
        .navigationTitle("Engine")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Paths", systemImage: "slider.horizontal.3") }.help("Tool paths")
            }
        }
        .confirmationDialog("Stop Apple Container?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop Engine", role: .destructive) { store.stopEngine() }
        } message: { Text("All running containers stop with it.") }
    }
    private var headline: String { switch store.engine {
    case .checking: "Connecting…"; case .missingCLI: "Apple Container is not installed"
    case .stopped: "Engine stopped"; case .running: "Engine running"
    } }
}

/// Edits a draft so half-typed paths never reach the running app; Apply or closing the window commits it.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @ViewState<RuntimeConfig?> private var draft: RuntimeConfig?
    var body: some View {
        let edited = Binding(get: { draft ?? store.config }, set: { draft = $0 })
        Form {
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
        .formStyle(.grouped)
        .disabled(store.bridgeOwned)
        .frame(width: 560, height: 480)
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
                Image(systemName: found ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(found ? Color.harbor : .orange)
                    .help(found ? "Found" : "No executable at this path")
            }
        } label: { Text(title) }
    }
}
