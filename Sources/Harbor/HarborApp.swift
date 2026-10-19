import SwiftUI
import AppKit
import HarborCore
import UniformTypeIdentifiers

// Explicit alias selects the property-wrapper type on SDKs that also export a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

@main struct HarborApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .frame(minWidth: 1000, minHeight: 680)
                .tint(Color(red: 0.20, green: 0.70, blue: 0.53))
        }
        .defaultSize(width: 1180, height: 790)
        .commands { CommandGroup(after: .newItem) { Button("Import Compose…") { store.importProject() }.keyboardShortcut("o") } }
        Settings { SettingsView().environmentObject(store).frame(width: 670, height: 540).padding(24) }
    }
}

private enum Page: String, CaseIterable, Identifiable {
    case containers = "Containers", images = "Images", build = "Build", networks = "Networks", volumes = "Volumes"
    case machines = "Linux Machines", registries = "Registries", kubernetes = "Kubernetes", commands = "Native Commands", runtime = "Runtime", projects = "Compose · Optional"
    var id: String { rawValue }
    var icon: String { switch self {
    case .containers: "shippingbox"; case .projects: "square.stack.3d.up"; case .images: "square.3.layers.3d"; case .runtime: "cpu"
    case .build: "hammer"; case .networks: "network"; case .volumes: "externaldrive"; case .machines: "desktopcomputer"; case .registries: "server.rack"; case .kubernetes: "hexagon"; case .commands: "terminal"
    } }
    var subtitle: String { switch self {
    case .containers: "Every container, connected directly to Apple Container."
    case .projects: "Enable the Docker compatibility layer when needed, without touching the native workflow."
    case .images: "OCI images, managed natively."
    case .runtime: "Lightweight runtime, native experience."
    case .build: "Apple Container's BuildKit builder."
    case .networks: "Isolated networks for local containers."
    case .volumes: "Keep data independent of container lifecycles."
    case .machines: "Persistent Linux development environments."
    case .registries: "Manage registry logins."
    case .kubernetes: "Official k8s plugin · experimental; capabilities follow the local version."
    case .commands: "Every native capability, with arguments matching the local help."
    } }
    /// The `NativeOperation` group whose actions this page offers; the sidebar label doubles as the group name.
    var group: String? { switch self {
    case .containers, .images, .build, .networks, .volumes, .machines, .registries, .kubernetes: rawValue
    case .commands, .runtime, .projects: nil
    } }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @ViewState<Page> private var page: Page = .containers
    @ViewState<String> private var search = ""
    @ViewState<Bool> private var runSheet = false
    @ViewState<Bool> private var pullSheet = false
    @ViewState<ContainerRow?> private var deleteTarget: ContainerRow?
    @ViewState<ImageRow?> private var deleteImage: ImageRow?
    private let green = Color(red: 0.20, green: 0.70, blue: 0.53)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 11) {
                    Image(systemName: "shippingbox.fill").font(.system(size: 26)).foregroundStyle(green)
                    VStack(alignment: .leading, spacing: 2) { Text("Harbor").font(.system(size: 23, weight: .semibold, design: .rounded)); Text("LOCAL, LIGHTER.").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(.secondary) }
                }.padding(.top, 20).padding(.bottom, 16)
                Text("Workspace").font(.caption).foregroundStyle(.secondary)
                ScrollView { VStack(spacing: 4) {
                    ForEach(Page.allCases) { item in
                        Button { page = item; search = "" } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon).frame(width: 20)
                                Text(item.rawValue).lineLimit(1).font(.callout)
                                Spacer()
                                if item == .containers { Text("\(store.containers.count)").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.horizontal, 12).padding(.vertical, 7)
                                .background(page == item ? green.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(page == item ? green : .primary)
                        }.buttonStyle(.plain)
                    }
                } }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Circle().fill(store.connected ? green : .orange).frame(width: 7, height: 7); Text(store.connected ? "Engine Connected" : "Waiting for Connection").font(.callout.weight(.medium)) }
                    Text("APPLE CONTAINER").font(.system(size: 9)).tracking(1.4).foregroundStyle(.secondary)
                    Button("Runtime & Compatibility →") { page = .runtime }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                HStack { Text("Harbor 0.2").font(.caption2); Spacer(); Text("PREVIEW").font(.system(size: 8, weight: .semibold)).tracking(1) }.foregroundStyle(.tertiary)
            }.padding(20).frame(width: 215).frame(maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Local Workspace", systemImage: "laptopcomputer").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if store.checking { ProgressView().controlSize(.small) }
                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh").disabled(store.busy)
                    SettingsLink { Image(systemName: "slider.horizontal.3") }
                }.buttonStyle(.borderless).padding(.horizontal, 30).padding(.vertical, 18)
                Divider()
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 7) { Text(page.rawValue).font(.system(size: 29, weight: .semibold)); Text(page.subtitle).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    if page == .containers { Button { runSheet = true } label: { Label("Create Container", systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(!store.connected || store.busy) }
                    if page == .projects { Button { store.importProject() } label: { Label("Import Project", systemImage: "plus") }.buttonStyle(.borderedProminent) }
                    if let group = page.group { Menu("Native Actions") { ForEach(NativeOperation.operations(in: group)) { op in Button(op.title) { store.nativeOperation = op } } }.fixedSize().disabled(store.busy) }
                    if page == .images { Button { pullSheet = true } label: { Label("Pull Image", systemImage: "arrow.down") }.buttonStyle(.borderedProminent).disabled(!store.connected || store.busy) }
                }.padding(30)
                if store.busy {
                    HStack { ProgressView().controlSize(.small); Text(store.outputTitle); Spacer(); Button("View Output") { store.showOutput = true }; Button("Stop Waiting") { store.cancel() } }.font(.caption).padding(12).background(green.opacity(0.08)).padding(.horizontal, 30).padding(.bottom, 16)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch page {
                        case .containers: containerPage
                        case .projects: projectPage
                        case .images: imagePage
                        case .runtime: RuntimeView()
                        case .build: NativeSection(group: "Build", list: ["builder", "status"])
                        case .networks: NativeSection(group: "Networks", list: ["network", "list"])
                        case .volumes: NativeSection(group: "Volumes", list: ["volume", "list"])
                        case .machines: NativeSection(group: "Linux Machines", list: ["machine", "list"])
                        case .registries: NativeSection(group: "Registries", list: ["registry", "list"])
                        case .kubernetes: NativeSection(group: "Kubernetes", list: ["k8s", "list"])
                        case .commands: NativeCatalogView()
                        }
                    }.padding(.horizontal, 30).padding(.bottom, 30)
                }
                Divider()
                HStack { Circle().fill(store.connected ? green : .orange).frame(width: 5, height: 5); Text(store.connected ? "Native CLI connected" : "Not connected · finish setup in Runtime"); Spacer(); Button("Activity") { store.showOutput = true } }.font(.caption2).foregroundStyle(.secondary).buttonStyle(.plain).padding(.horizontal, 30).padding(.vertical, 12)
            }.background(Color(nsColor: .controlBackgroundColor))
        }
        .task { await store.refresh(); while !Task.isCancelled { try? await Task.sleep(for: .seconds(8)); if !Task.isCancelled { await store.refresh() } } }
        .sheet(item: $store.nativeOperation) { operation in NativeOperationSheet(initial: operation).environmentObject(store) }
        .task(id: page) { if page == .projects { await store.refreshCompatibility() } }
        .sheet(isPresented: $runSheet) { RunSheet().environmentObject(store) }
        .sheet(isPresented: $pullSheet) { PullSheet().environmentObject(store) }
        .sheet(isPresented: $store.showOutput) { OutputSheet().environmentObject(store) }
        .confirmationDialog("Delete container \(deleteTarget?.name ?? "")? Its writable layer will be lost.", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete Container", role: .destructive) { if let c = deleteTarget { store.perform("Delete Container", command: store.config.nativeCommand(["delete", c.id])) }; deleteTarget = nil }
        }
        .confirmationDialog("Delete local image \(deleteImage?.reference ?? "")?", isPresented: Binding(get: { deleteImage != nil }, set: { if !$0 { deleteImage = nil } }), titleVisibility: .visible) {
            Button("Delete Image", role: .destructive) { if let i = deleteImage { store.perform("Delete Image", command: store.config.nativeCommand(["image", "delete", i.reference])) }; deleteImage = nil }
        }
    }
    private var containerPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) { Metric(title: "Containers", value: "\(store.containers.count)", icon: "shippingbox"); Metric(title: "Running", value: "\(store.containers.filter(\.running).count)", icon: "play.circle"); Metric(title: "Local Images", value: "\(store.images.count)", icon: "square.3.layers.3d") }
            searchField
            if !store.connected { setupCard }
            else if store.containers.isEmpty { EmptyCard(icon: "shippingbox", title: "Your workspace is ready", detail: "Create your first container, or import an existing Compose project.") }
            else {
                let rows = store.containers.filter { search.isEmpty || ($0.name + $0.image).localizedCaseInsensitiveContains(search) }
                if rows.isEmpty { EmptyCard(icon: "magnifyingglass", title: "No matching containers", detail: "Try another name or image.") }
                ForEach(rows) { c in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill").font(.title2).foregroundStyle(c.running ? green : .secondary).frame(width: 42, height: 42).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) { Text(c.name).font(.headline); Text(c.image).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text(c.state).font(.caption.weight(.medium)).foregroundStyle(c.running ? green : .secondary).padding(.horizontal, 9).padding(.vertical, 4).background((c.running ? green : .gray).opacity(0.10), in: Capsule())
                            Button { store.perform(c.running ? "Stop Container" : "Start Container", command: store.config.nativeCommand([c.running ? "stop" : "start", c.id])) } label: { Image(systemName: c.running ? "stop.fill" : "play.fill") }.help(c.running ? "Stop" : "Start")
                            Menu { Button("Inspect") { store.perform("Container Details", command: store.config.nativeCommand(["inspect", c.id])) }; Button("Stats") { store.perform("Stats", command: store.config.nativeCommand(["stats", "--no-stream", c.id])) }; Button("Delete…", role: .destructive) { deleteTarget = c }.disabled(c.running) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
                        }
                        HStack { Text(c.status).foregroundStyle(.secondary); if !c.ports.isEmpty { Text("·"); Text(c.ports).textSelection(.enabled).lineLimit(2) }; Spacer(); Button("Logs") { store.perform("\(c.name) · Logs", command: store.config.nativeCommand(["logs", "-n", "300", c.id])) }; Button("Terminal ↗") { store.openTerminal(c) }.disabled(!c.running) }.font(.caption)
                    }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary)).disabled(store.busy)
                }
            }
        }
    }
    private var projectPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Optional Docker compatibility extension; native features need neither Docker nor Socktainer.", systemImage: "puzzlepiece.extension").font(.callout).foregroundStyle(.secondary)
            DisclosureGroup("Set Up the Docker / Compose Compatibility Layer") { CompatibilityView() }
            if store.projects.isEmpty { EmptyCard(icon: "square.stack.3d.up", title: "Bring your existing projects", detail: "Choose compose.yaml or docker-compose.yml. Multiple files can be layered and their override order adjusted.") }
            ForEach(store.projects) { project in
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Image(systemName: "folder.fill").foregroundStyle(green); Text(project.name).font(.headline); Spacer(); Button("Remove from List") { store.removeProject(project) }.buttonStyle(.borderless).font(.caption) }
                    Text(project.directory).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    ForEach(Array(project.files.enumerated()), id: \.offset) { index, file in
                        HStack { Text("\(index + 1). \(URL(fileURLWithPath: file).lastPathComponent)").font(.system(.caption, design: .monospaced)); Spacer(); if index > 0 { Button("Move Up") { store.moveFileUp(project, at: index) }.font(.caption) } }
                    }
                    if store.dockerConnected { services(of: project) }
                    Divider()
                    HStack { ForEach(ComposeAction.allCases) { action in Button(action.rawValue) { store.compose(project, action) }.disabled(store.busy || (action.needsDocker && !store.dockerConnected)) }; Spacer(); Button { store.copy(store.config.composeCommand(project, ["up", "--detach"]).display) } label: { Image(systemName: "doc.on.doc") }.help("Copy the full up command") }
                }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            }
            Text("Stop keeps containers and volumes. Remove from List only removes this app's project record. Compatibility depends on Socktainer; verify your project before migrating data.").font(.caption).foregroundStyle(.secondary)
        }
    }
    /// The project's containers as `docker compose ps` reports them.
    @ViewBuilder private func services(of project: ComposeProject) -> some View {
        switch store.services[project.id] {
        case .success(let rows)?:
            if rows.isEmpty { Text("No containers yet. Start creates them.").font(.caption).foregroundStyle(.secondary) }
            ForEach(rows) { c in HStack(spacing: 8) { Circle().fill(c.running ? green : .secondary).frame(width: 6, height: 6); Text(c.name).font(.system(.caption, design: .monospaced)); Text(c.status).font(.caption).foregroundStyle(.secondary); Spacer(); Text(c.ports).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1) } }
        case .failure(let error)?: Text("Could not read services: " + error.localizedDescription).font(.caption).foregroundStyle(.orange).lineLimit(3).textSelection(.enabled)
        case nil: EmptyView()
        }
    }
    private var imagePage: some View {
        VStack(spacing: 18) {
            searchField
            if !store.connected { setupCard }
            else if store.images.isEmpty { EmptyCard(icon: "square.3.layers.3d", title: "Start with an image", detail: "Pull nginx, redis or your project's images.") }
            ForEach(store.images.filter { search.isEmpty || $0.reference.localizedCaseInsensitiveContains(search) }) { i in
                HStack(spacing: 14) { Image(systemName: "square.3.layers.3d").font(.title2).foregroundStyle(green); VStack(alignment: .leading, spacing: 5) { Text(i.repository).font(.headline); Text(i.tag + "  ·  " + i.size).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(String(i.digest.prefix(19))).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary); Button { deleteImage = i } label: { Image(systemName: "trash") }.disabled(store.busy) }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            }
        }
    }
    private var searchField: some View { HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search names or images…", text: $search).textFieldStyle(.plain) }.padding(11).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)) }
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 16) { Label("Connect Your Apple Container", systemImage: "cable.connector").font(.title3.weight(.semibold)); Text("Install the official container CLI to get started. Containers, images, networks, volumes and builds all use the native engine directly.").foregroundStyle(.secondary); HStack { Button("Set Up Runtime →") { page = .runtime }.buttonStyle(.borderedProminent); Button("Check Again") { Task { await store.refresh() } } } }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(green.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct Metric: View {
    var title: String; var value: String; var icon: String
    var body: some View { VStack(alignment: .leading, spacing: 15) { HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(.secondary) }; Text(value).font(.system(size: 29, weight: .medium, design: .rounded)) }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary)) }
}
struct EmptyCard: View {
    var icon: String; var title: String; var detail: String
    var body: some View { VStack(spacing: 15) { Image(systemName: icon).font(.system(size: 42, weight: .light)).foregroundStyle(.secondary); Text(title).font(.title3.weight(.medium)); Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(45).frame(maxWidth: .infinity) }
}

struct CompatibilityView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Image(systemName: "cpu").font(.largeTitle).foregroundStyle(.mint); VStack(alignment: .leading, spacing: 5) { Text(store.dockerConnected ? "Runtime Connected" : "Set up once, then get to work").font(.title3.weight(.semibold)); Text("Apple Container → Socktainer → Docker CLI / Compose").font(.caption).foregroundStyle(.secondary) }; Spacer() }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    dependency("Apple Container", path: store.config.container)
                    dependency("Socktainer", path: store.config.socktainer)
                    dependency("Docker CLI", path: store.config.docker)
                    Divider()
                    Text("Run diagnostics to confirm the Compose plugin status.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Start Compatibility Service") { store.startBridge() }.buttonStyle(.borderedProminent).disabled(store.busy || store.bridgeOwned || store.dockerConnected); Button("Diagnostics") { store.diagnostics() }.disabled(store.busy); Button("Service Logs") { store.readBridgeLog() }.disabled(store.busy); if store.bridgeOwned { Button("Stop Compatibility Service") { store.stopOwnedBridge() }.disabled(store.busy) } }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(store.connectionMessage).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(5)
            GroupBox("Install Dependencies") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Requires Apple Silicon and macOS 26 or later. Install these components with Homebrew, then check the paths in Settings.").font(.callout)
                    HStack { Text("brew install container socktainer docker docker-compose").font(.system(.caption, design: .monospaced)).textSelection(.enabled); Spacer(); Button("Copy") { store.copy("brew install container socktainer docker docker-compose") } }
                    Text("If docker compose version cannot find the plugin, configure cliPluginsExtraDirs as the Homebrew docker-compose caveats describe; keep your existing Docker config.").font(.caption).foregroundStyle(.secondary)
                    HStack { Link("Apple Container ↗", destination: URL(string: "https://github.com/apple/container")!); Link("Socktainer ↗", destination: URL(string: "https://github.com/socktainer/socktainer")!); SettingsLink { Text("Configure Paths…") } }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Docker CLI Access") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("After creating a dedicated context, use docker --context harbor-apple compose up -d. Harbor never switches the global default context.").font(.callout)
                    HStack { Button("Create harbor-apple Context") { store.perform("Create Docker Context", command: store.config.dockerCommand(["context", "create", "harbor-apple", "--docker", "host=unix://" + store.config.socket])) }.disabled(store.busy || !store.dockerConnected); Button("Copy Direct Command") { store.copy(store.config.dockerCommand(["ps"]).display) } }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Compatibility Scope · Preview") {
                Text("Compose uses the official client; Socktainer provides partial Docker API compatibility. Interactive terminals use Apple container exec; pause, dynamic network attach and full privileged behavior are not equivalent to Docker Engine. Images, named volumes and database data are not migrated from OrbStack automatically. Before switching for real, verify builds, service discovery, health checks and data persistence with your own project.").font(.callout).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    func dependency(_ name: String, path: String) -> some View {
        HStack { Image(systemName: FileManager.default.isExecutableFile(atPath: path) ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(FileManager.default.isExecutableFile(atPath: path) ? .green : .orange); Text(name).frame(width: 110, alignment: .leading); Text(path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled); Spacer() }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Runtime Settings").font(.title2.weight(.semibold))
            Text("Apple Container is the core dependency; Docker, Socktainer and the socket are only for the optional Compose extension.").foregroundStyle(.secondary)
            Form { TextField("Docker CLI", text: $store.config.docker); TextField("Apple Container", text: $store.config.container); TextField("Socktainer", text: $store.config.socktainer); TextField("Unix socket", text: $store.config.socket) }.textFieldStyle(.roundedBorder).disabled(store.busy || store.bridgeOwned)
            HStack { Button("Find Tools Automatically") { store.config.docker = RuntimeConfig.find("docker"); store.config.container = RuntimeConfig.find("container"); store.config.socktainer = RuntimeConfig.find("socktainer"); store.save() }; Button("Save and Check") { store.save(); Task { await store.refresh() } }.buttonStyle(.borderedProminent) }.disabled(store.busy || store.bridgeOwned)
            Text("Once the compatibility service is running, stop it before changing paths. The app only controls the Socktainer it started; Apple Container and containers run independently.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct RunSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @ViewState<RunOptions> private var options = RunOptions()
    @ViewState<String?> private var validation: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create Container").font(.title2.weight(.semibold))
            Form { TextField("Image", text: $options.image); TextField("Name (optional)", text: $options.name); TextField("Port Mappings", text: $options.ports); TextField("Volume (optional)", text: $options.volume); Stepper("CPU · \(options.cpus)", value: $options.cpus, in: 1...16); TextField("Memory", text: $options.memory) }.textFieldStyle(.roundedBorder)
            DisclosureGroup("Advanced Native Options") { VStack(alignment: .leading, spacing: 10) { TextField("Extra run arguments, e.g. --network dev-net --arch arm64", text: $options.extraOptions); TextField("Command inside the container; leave empty for the image default", text: $options.command); Text("Any native container run argument is accepted, with quoting; no shell expansion.").font(.caption).foregroundStyle(.secondary) }.textFieldStyle(.roundedBorder) }
            Text("Environment Variables · one KEY=value per line").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $options.environment).font(.system(.body, design: .monospaced)).frame(height: 80).border(.quaternary)
            Text("Port example: 127.0.0.1:8080:80 (separate several with commas); volume example: /host/path:/container/path").font(.caption).foregroundStyle(.secondary)
            if let validation { Text(validation).foregroundStyle(.red).font(.caption) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Create and Start") { do { let args = try options.arguments(); dismiss(); Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); store.perform("Create Container", command: store.config.nativeCommand(args), timeout: 1200) } } catch { validation = error.localizedDescription } }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 580)
    }
}
struct PullSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var image = "nginx:alpine"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) { Text("Pull Image").font(.title2.weight(.semibold)); TextField("registry/repository:tag", text: $image).textFieldStyle(.roundedBorder); HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Pull") { let reference = image.trimmingCharacters(in: .whitespacesAndNewlines); dismiss(); Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); store.perform("Pull Image", command: store.config.nativeCommand(["image", "pull", reference]), timeout: 1200) } }.buttonStyle(.borderedProminent).disabled(!ImageReference.isValid(image.trimmingCharacters(in: .whitespacesAndNewlines))) } }.padding(28).frame(width: 480)
    }
}
struct OutputSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { if store.outputFailed { Label("Failed", systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout.weight(.medium)) }; Text(store.outputTitle).font(.title3.weight(.semibold)); Spacer(); if store.busy { ProgressView().controlSize(.small); Button("Stop Waiting") { store.cancel() } }; Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) { Text(store.output.isEmpty ? (store.busy ? "Running…" : "Operation results appear here.") : store.output).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(16); Color.clear.frame(height: 1).id("end") }
                }.background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(Color(white: 0.90))
                .onChange(of: store.output) { _, _ in if store.busy { proxy.scrollTo("end", anchor: .bottom) } }
            }
            HStack { Text(store.busy ? "Output streams in as the command writes it. Stop Waiting does not roll back the backend operation." : "Output may contain app logs or environment variables; review it before sharing.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Copy") { store.copy(store.output) } }
        }.padding(24).frame(width: 820, height: 520)
    }
}
