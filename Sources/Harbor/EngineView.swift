import SwiftUI
import HarborCore

/// What to do next when the engine cannot be reached: install the CLI, or start the engine.
struct EngineSetupView: View {
    @Environment(Store.self) private var store
    var body: some View {
        switch store.engine {
        case .checking, .running:
            ProgressView("Connecting to Apple Container…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .missingCLI:
            ContentUnavailableView {
                Label("Install Apple Container", systemImage: "shippingbox")
            } description: {
                Text("Harbor manages Apple's official container runtime, which needs Apple silicon and macOS 26 or later. Install it, then Harbor connects on its own.")
            } actions: {
                Button("Copy “brew install container”") { store.copy("brew install container") }.buttonStyle(.borderedProminent)
                Link("Download the Installer", destination: URL(string: "https://github.com/apple/container/releases")!)
                SettingsLink { Text("Use a Different Path…") }
            }
        case .stopped(let reason):
            ContentUnavailableView {
                Label("Engine Not Running", systemImage: "power")
            } description: {
                Text("Start Apple Container to see containers and images. The first start downloads the recommended Linux kernel.")
                Text(reason).font(.caption).foregroundStyle(.tertiary).lineLimit(3).textSelection(.enabled)
            } actions: {
                Button { store.startEngine() } label: {
                    HStack(spacing: 6) {
                        if store.isBusy("engine") { ProgressView().controlSize(.small) }
                        Text(store.isBusy("engine") ? "Starting…" : "Start Engine")
                    }
                }
                .buttonStyle(.borderedProminent).disabled(store.isBusy("engine"))
            }
        }
    }
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
                if case .missingCLI = store.engine { EngineSetupView().frame(height: 300).card() }
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

struct SettingsView: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                PathField(title: "container CLI", path: $store.config.container)
            } header: { Text("Apple Container") } footer: { Text("Every native action runs this executable directly, never through a shell.") }
            Section {
                PathField(title: "Docker CLI", path: $store.config.docker)
                PathField(title: "Socktainer", path: $store.config.socktainer)
                TextField("Socket", text: $store.config.socket).font(.callout.monospaced())
            } header: { Text("Docker and Compose (optional)") } footer: {
                Text("Docker commands always use this socket explicitly, and inherited Docker context variables are cleared.")
            }
            Section {
                HStack {
                    Button("Detect Automatically") { store.detectTools() }
                    Spacer()
                    Button("Apply") { store.applySettings() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            } footer: {
                if store.bridgeOwned { Text("Stop the compatibility service before changing paths.") }
            }
        }
        .formStyle(.grouped)
        .disabled(store.bridgeOwned)
        .frame(width: 560, height: 480)
        .onDisappear { store.applySettings() }
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
