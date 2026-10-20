import SwiftUI
import HarborCore

struct ComposeView: View {
    @Environment(Store.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CompatibilityCard()
                if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No Compose Projects", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("Import compose.yaml, plus any override files. Harbor runs the real Docker Compose against Apple Container through Socktainer.")
                    } actions: {
                        Button("Import Compose Project…") { store.importProject() }.buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 24)
                }
                ForEach(store.projects) { ProjectCard(project: $0) }
            }
            .padding(20)
            .animation(.smooth, value: store.projects)
        }
        .navigationTitle("Compose")
        .navigationSubtitle("Optional · via Socktainer")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.importProject() } label: { Label("Import Project", systemImage: "plus") }.help("Import a Compose project (⌘O)")
            }
        }
        .task { await store.refreshCompatibility() }
    }
}

private struct CompatibilityCard: View {
    @Environment(Store.self) private var store
    @ViewState<Bool> private var showDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(store.dockerConnected ? Color.harborLive : .orange).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.dockerConnected ? "Docker API ready" : "Compatibility service not running").font(.headline)
                    Text("Only Compose needs this. Native containers, images and builds never do.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isBusy("bridge") { ProgressView().controlSize(.small) }
                if store.bridgeOwned {
                    Button("Stop Service") { store.stopOwnedBridge() }
                } else if !store.dockerConnected {
                    Button("Start Service") { store.startBridge() }.buttonStyle(.borderedProminent).disabled(store.isBusy("bridge"))
                }
            }
            DisclosureGroup("Setup and diagnostics", isExpanded: $showDetails) { details.padding(.top, 8) }
        }
        .card()
        .animation(.smooth, value: store.dockerConnected)
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                dependency("Apple Container", store.config.container)
                dependency("Socktainer", store.config.socktainer)
                dependency("Docker CLI", store.config.docker)
            }
            HStack {
                Text("brew install socktainer docker docker-compose").font(.callout.monospaced()).textSelection(.enabled)
                Button { store.copy("brew install socktainer docker docker-compose") } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy")
            }
            HStack {
                Button("Diagnostics") { store.diagnostics() }
                Button("Service Log") { store.showBridgeLog() }
                Button("Create harbor-apple Context") { store.createDockerContext() }.disabled(!store.dockerConnected)
                    .help("Lets docker --context harbor-apple reach Apple Container. Harbor never switches your default context.")
                Spacer()
                SettingsLink { Text("Paths…") }
            }
            Text("Socktainer provides partial Docker API compatibility. Images, volumes and data from other Docker engines are not migrated; verify builds, networking and persistence with your own project.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func dependency(_ name: String, _ path: String) -> some View {
        let found = FileManager.default.isExecutableFile(atPath: path)
        return GridRow {
            Image(systemName: found ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(found ? Color.harborLive : .orange)
            Text(name)
            Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

private struct ProjectCard: View {
    @Environment(Store.self) private var store
    let project: ComposeProject
    @ViewState<Bool> private var showFiles = false
    @ViewState<Bool> private var confirmRemove = false
    @ViewState<ComposeAction?> private var pendingAction: ComposeAction?
    var body: some View {
        let busy = store.isBusy(project.id.uuidString)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RowIcon(systemName: "square.stack.3d.up.fill").symbolEffect(.pulse, isActive: busy)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.headline)
                    Text(project.directory).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button { store.compose(project, .start) } label: { Label("Up", systemImage: "play.fill") }
                    .disabled(busy || !store.dockerConnected).help("docker compose up --detach")
                Button { store.compose(project, .stop) } label: { Label("Stop", systemImage: "stop.fill") }
                    .disabled(busy || !store.dockerConnected)
                Menu {
                    ForEach([ComposeAction.restart, .pull, .build]) { action in
                        Button(action.rawValue) { store.compose(project, action) }.disabled(busy || !store.dockerConnected)
                    }
                    Divider()
                    ForEach([ComposeAction.logs, .status, .validate]) { action in
                        Button(action.rawValue) { store.compose(project, action) }.disabled(busy || (action.needsDocker && !store.dockerConnected))
                    }
                    Divider()
                    Button("Down…") { pendingAction = .down }.disabled(busy || !store.dockerConnected)
                    Button("Down and Delete Volumes…", role: .destructive) { pendingAction = .downWithVolumes }.disabled(busy || !store.dockerConnected)
                    Divider()
                    Button("Reveal in Finder") { store.reveal(project.files[0]) }
                    Button("Copy Up Command") { store.copy(store.config.composeCommand(project, ComposeAction.start.arguments).display) }
                    Divider()
                    Button("Remove from Harbor…", role: .destructive) { confirmRemove = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More actions for \(project.name)")
            }
            if store.dockerConnected { services(busy: busy) }
            DisclosureGroup("Files (\(project.files.count))", isExpanded: $showFiles) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(project.files.enumerated()), id: \.offset) { index, file in
                        HStack {
                            Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                            Text(URL(fileURLWithPath: file).lastPathComponent).font(.callout.monospaced()).help(file)
                            Spacer()
                            Button { store.moveFile(project, from: index, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                                .accessibilityLabel("Move up")
                            Button { store.moveFile(project, from: index, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == project.files.count - 1)
                                .accessibilityLabel("Move down")
                        }
                        .buttonStyle(.borderless)
                    }
                    Text("Later files override earlier ones.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        }
        .card()
        .confirmationDialog("Remove “\(project.name)” from Harbor?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { store.removeProject(project) }
        } message: { Text("Only Harbor's record is removed. Files, containers and volumes stay as they are.") }
        .confirmationDialog(pendingAction == .downWithVolumes ? "Take down “\(project.name)” and delete its volumes?" : "Take down “\(project.name)”?",
                            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible,
                            presenting: pendingAction) { action in
            Button(action == .downWithVolumes ? "Down and Delete Volumes" : "Down", role: .destructive) { store.compose(project, action) }
        } message: { action in
            Text(action == .downWithVolumes
                 ? "Containers and networks are removed, and so is the data in the project's named volumes. This cannot be undone."
                 : "Containers and networks are removed. Named volumes and images are kept, so Up brings the project back with its data.")
        }
    }
    @ViewBuilder private func services(busy: Bool) -> some View {
        switch store.services[project.id] {
        case .success(let rows)?:
            if rows.isEmpty {
                Text("No containers yet. Up creates them.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(rows) { c in
                        HStack(spacing: 8) {
                            Circle().fill(c.running ? Color.harborLive : .secondary).frame(width: 7, height: 7)
                            Text(c.service.isEmpty ? c.name : c.service).font(.callout.monospaced()).lineLimit(1).help(c.name)
                            Text(c.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            PortLinks(mappings: c.portMappings)
                            if !c.service.isEmpty { serviceMenu(c, busy: busy) }
                        }
                    }
                }
            }
        case .failure(let error)?:
            Label("Could not read services: " + error.localizedDescription, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).lineLimit(3).textSelection(.enabled)
        case nil:
            EmptyView()
        }
    }
    private func serviceMenu(_ c: ContainerRow, busy: Bool) -> some View {
        Menu {
            if c.running {
                Button("Stop") { store.compose(project, .stop, service: c.service) }
                Button("Restart") { store.compose(project, .restart, service: c.service) }
            } else {
                Button("Start") { store.compose(project, .start, service: c.service) }
            }
            Button("Logs") { store.compose(project, .logs, service: c.service) }
            Divider()
            Button("Pull") { store.compose(project, .pull, service: c.service) }
            Button("Build") { store.compose(project, .build, service: c.service) }
        } label: { Image(systemName: "ellipsis.circle") }
        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
        .disabled(busy)
        .help("Actions for the \(c.service) service")
        .accessibilityLabel("Actions for the \(c.service) service")
    }
}
