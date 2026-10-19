import SwiftUI
import HarborCore

enum ContainerFilter: String, CaseIterable, Identifiable {
    case all = "All", running = "Running", stopped = "Stopped"
    var id: String { rawValue }
}

enum ContainerSort: String, CaseIterable, Identifiable {
    case name = "Name", image = "Image", state = "State", created = "Newest First"
    var id: String { rawValue }
    func ordered(_ rows: [ContainerRow]) -> [ContainerRow] {
        switch self {
        case .name: rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .image: rows.sorted { ($0.image, $0.name) < ($1.image, $1.name) }
        case .state: rows.sorted { ($0.running ? 0 : 1, $0.name) < ($1.running ? 0 : 1, $1.name) }
        case .created: rows.sorted { ($0.details?.created ?? .distantPast) > ($1.details?.created ?? .distantPast) }
        }
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case overview = "Overview", logs = "Logs", stats = "Stats", files = "Files", inspect = "Inspect"
    var id: String { rawValue }
}

struct ContainersView: View {
    @Environment(Store.self) private var store
    @ViewState<String> private var search = ""
    @ViewState<ContainerFilter> private var filter: ContainerFilter = .all
    @ViewState<ContainerSort> private var sort: ContainerSort = .name
    @ViewState<Set<String>> private var selection: Set<String> = []
    @ViewState<Bool> private var showInspector = false
    @ViewState<InspectorTab> private var tab: InspectorTab = .overview
    @ViewState<[ContainerRow]> private var pendingDelete: [ContainerRow] = []

    private var rows: [ContainerRow] {
        sort.ordered(store.containers.filter { c in
            (filter == .all || c.running == (filter == .running))
                && (search.isEmpty || (c.name + " " + c.image).localizedCaseInsensitiveContains(search))
        })
    }
    /// The inspector follows a single selection.
    private var selected: ContainerRow? { selection.count == 1 ? store.containers.first { selection.contains($0.id) } : nil }

    var body: some View {
        content
            .navigationTitle("Containers")
            .navigationSubtitle(subtitle)
            .searchable(text: $search, placement: .toolbar, prompt: "Name or image")
            .toolbar { toolbar }
            .inspector(isPresented: $showInspector) {
                ContainerInspector(container: selected, selectionCount: selection.count, tab: $tab, onDelete: { pendingDelete = [$0] })
                    .inspectorColumnWidth(min: 320, ideal: 400, max: 600)
            }
            .confirmationDialog(deleteTitle, isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
                                titleVisibility: .visible) {
                Button(pendingDelete.contains(where: \.running) ? "Stop and Delete" : "Delete", role: .destructive) { pendingDelete.forEach { store.delete($0) } }
            } message: { Text("The containers' writable layers are removed. Images and volumes are kept.") }
    }
    private var deleteTitle: String {
        pendingDelete.count == 1 ? "Delete “\(pendingDelete[0].name)”?" : "Delete \(pendingDelete.count) containers?"
    }

    private var subtitle: String {
        guard store.engine.isRunning else { return "" }
        let running = store.containers.filter(\.running).count
        return "\(running) running · \(store.containers.count) total"
    }

    @ViewBuilder private var content: some View {
        if !store.engine.isRunning {
            EngineSetupView()
        } else if store.containers.isEmpty {
            ContentUnavailableView {
                Label("No Containers", systemImage: "shippingbox")
            } description: {
                Text("Run a container from an image. It starts in the background and shows up here.")
            } actions: {
                Button("Run Container…") { store.present(.run(RunOptions())) }.buttonStyle(.borderedProminent)
                Button("Pull an Image…") { store.present(.pull) }
            }
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            List(selection: $selection) {
                ForEach(rows) { ContainerListRow(container: $0) }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let chosen = store.containers.filter { ids.contains($0.id) }
                if chosen.count == 1, let c = chosen.first { menu(for: c) }
                else if !chosen.isEmpty { bulkMenu(for: chosen) }
            } primaryAction: { ids in
                selection = ids; tab = .overview; showInspector = true
            }
            .animation(.smooth, value: rows)
        }
    }

    /// Actions for several selected containers; each one runs as its own job.
    @ViewBuilder private func bulkMenu(for chosen: [ContainerRow]) -> some View {
        let stopped = chosen.filter { !$0.running && !store.isBusy($0.id) }
        let running = chosen.filter { $0.running && !store.isBusy($0.id) }
        Button("Start \(stopped.count) Containers") { stopped.forEach { store.start($0) } }.disabled(stopped.isEmpty)
        Button("Stop \(running.count) Containers") { running.forEach { store.stop($0) } }.disabled(running.isEmpty)
        Button("Restart \(running.count) Containers") { running.forEach { store.restart($0) } }.disabled(running.isEmpty)
        Divider()
        Button("Copy IDs") { store.copy(chosen.map(\.id).joined(separator: "\n")) }
        Divider()
        Button("Delete \(chosen.count) Containers…", role: .destructive) { pendingDelete = chosen }
    }

    @ViewBuilder private func menu(for c: ContainerRow) -> some View {
        let busy = store.isBusy(c.id)
        if c.running {
            Button("Stop") { store.stop(c) }.disabled(busy)
            Button("Restart") { store.restart(c) }.disabled(busy)
            Button("Open Shell in Terminal") { store.openShell(c) }
        } else {
            Button("Start") { store.start(c) }.disabled(busy)
        }
        Divider()
        Button("Show Details") { show(c, .overview) }
        Button("Show Logs") { show(c, .logs) }
        Button("Show Stats") { show(c, .stats) }.disabled(!c.running)
        Button("Browse Files") { show(c, .files) }.disabled(!c.running)
        ForEach(c.portMappings.compactMap(\.url), id: \.self) { url in Link("Open \(url.host() ?? ""):\(url.port ?? 0)", destination: url) }
        Button("Copy ID") { store.copy(c.id) }
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = [c] }.disabled(busy)
    }
    private func show(_ c: ContainerRow, _ section: InspectorTab) { selection = [c.id]; tab = section; showInspector = true }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Show", selection: $filter) { ForEach(ContainerFilter.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).fixedSize()
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: $sort) { ForEach(ContainerSort.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.inline)
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            .help("Sort containers")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { store.present(.run(RunOptions())) } label: { Label("Run Container", systemImage: "plus") }
                .disabled(!store.engine.isRunning).help("Run a new container (⌘N)")
        }
        ToolbarItem(placement: .primaryAction) { NativeActionsMenu(group: "Containers") }
        ToolbarItem(placement: .primaryAction) {
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }.help("Show or hide details")
        }
    }
}

private struct ContainerListRow: View {
    @Environment(Store.self) private var store
    let container: ContainerRow
    @ViewState<Bool> private var hovering = false
    var body: some View {
        let busy = store.isBusy(container.id)
        HStack(spacing: 12) {
            RowIcon(systemName: "shippingbox.fill", active: container.running)
                .symbolEffect(.pulse, isActive: busy)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name).font(.body.weight(.medium)).lineLimit(1)
                Text(container.image).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minWidth: 140, alignment: .leading)
            Spacer(minLength: 12)
            PortLinks(mappings: container.portMappings)
            StateBadge(state: container.state, running: container.running)
            HStack(spacing: 4) {
                if busy {
                    ProgressView().controlSize(.small).frame(width: 24)
                } else {
                    Button { container.running ? store.stop(container) : store.start(container) } label: {
                        Image(systemName: container.running ? "stop.fill" : "play.fill").contentTransition(.symbolEffect(.replace))
                    }
                    .help(container.running ? "Stop" : "Start")
                    Button { store.openShell(container) } label: { Image(systemName: "terminal") }
                        .help("Open a shell in Terminal").disabled(!container.running)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .buttonStyle(.borderless)
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.smooth, value: busy)
    }
}

private struct ContainerInspector: View {
    @Environment(Store.self) private var store
    let container: ContainerRow?
    let selectionCount: Int
    @Binding var tab: InspectorTab
    let onDelete: (ContainerRow) -> Void
    var body: some View {
        if let container {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) { ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().padding(12)
                switch tab {
                case .overview: ContainerOverview(container: container, onDelete: onDelete)
                case .logs: ContainerLogs(container: container)
                case .stats: ContainerStatsView(container: container)
                case .files: ContainerFilesView(container: container)
                case .inspect: ContainerJSON(container: container)
                }
            }
        } else if selectionCount > 1 {
            ContentUnavailableView("\(selectionCount) Containers Selected", systemImage: "square.stack",
                                   description: Text("Right-click the selection to start, stop or delete them together."))
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.trailing", description: Text("Select a container to see its details and logs."))
        }
    }
}

private struct ContainerOverview: View {
    @Environment(Store.self) private var store
    let container: ContainerRow
    let onDelete: (ContainerRow) -> Void
    @ViewState<Bool> private var showValues = false
    var body: some View {
        let busy = store.isBusy(container.id)
        let details = container.details
        Form {
            Section {
                LabeledContent("State") { StateBadge(state: container.state, running: container.running) }
                LabeledContent("Image") { Text(container.image).textSelection(.enabled) }
                LabeledContent("Resources") { Text(container.status).textSelection(.enabled) }
                LabeledContent("Ports") {
                    if container.portMappings.isEmpty { Text("None").foregroundStyle(.secondary) }
                    else { VStack(alignment: .trailing, spacing: 4) { PortLinks(mappings: container.portMappings, limit: 8) } }
                }
                if let created = details?.created { LabeledContent("Created") { Text(created, format: .relative(presentation: .named)) }.help(created.formatted()) }
                if container.running, let started = details?.started { LabeledContent("Started") { Text(started, format: .relative(presentation: .named)) }.help(started.formatted()) }
                if let platform = details?.platform, !platform.isEmpty { LabeledContent("Platform", value: platform) }
                LabeledContent("ID") { Text(container.id).font(.callout.monospaced()).textSelection(.enabled) }
            }
            Section {
                if container.running {
                    Button("Stop") { store.stop(container) }.disabled(busy)
                    Button("Restart") { store.restart(container) }.disabled(busy)
                    Button("Open Shell in Terminal") { store.openShell(container) }
                } else {
                    Button("Start") { store.start(container) }.disabled(busy)
                }
                Button("Delete…", role: .destructive) { onDelete(container) }.disabled(busy)
            }
            if let details {
                Section("Process") {
                    if !details.command.isEmpty { LabeledContent("Command") { Text(details.command.map(Command.quote).joined(separator: " ")).font(.callout.monospaced()).textSelection(.enabled) } }
                    if !details.workingDirectory.isEmpty { LabeledContent("Working Directory") { Text(details.workingDirectory).font(.callout.monospaced()).textSelection(.enabled) } }
                    if !details.user.isEmpty { LabeledContent("User") { Text(details.user).font(.callout.monospaced()) } }
                }
                if !details.networks.isEmpty {
                    Section("Networks") {
                        ForEach(details.networks, id: \.self) { network in
                            LabeledContent(network.name) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(network.address.isEmpty ? "Not connected" : network.address).font(.callout.monospaced()).textSelection(.enabled)
                                        .foregroundStyle(network.address.isEmpty ? .secondary : .primary)
                                    if !network.hostname.isEmpty { Text(network.hostname).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                }
                            }
                        }
                    }
                }
                if !details.mounts.isEmpty {
                    Section("Mounts") {
                        ForEach(details.mounts, id: \.self) { mount in
                            LabeledContent {
                                Text(mount.kind == "tmpfs" ? "tmpfs" : mount.source).font(.caption.monospaced()).lineLimit(2).truncationMode(.middle)
                                    .textSelection(.enabled).help(mount.source)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mount.kind == "volume" ? "externaldrive" : mount.kind == "bind" ? "folder" : "memorychip")
                                        .foregroundStyle(.secondary).accessibilityLabel(mount.kind)
                                    Text(mount.destination).font(.callout.monospaced())
                                    if mount.readOnly { Text("read-only").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
                if !details.environment.isEmpty {
                    Section {
                        ForEach(details.environment, id: \.self) { entry in
                            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
                            LabeledContent(parts.first ?? entry) {
                                Text(showValues ? (parts.count > 1 ? parts[1] : "") : "••••••").font(.caption.monospaced())
                                    .lineLimit(3).textSelection(.enabled)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Environment")
                            Spacer()
                            Button(showValues ? "Hide Values" : "Show Values") { showValues.toggle() }.buttonStyle(.borderless).font(.caption)
                        }
                    }
                }
                if !details.labels.isEmpty {
                    Section("Labels") {
                        ForEach(details.labels.keys.sorted(), id: \.self) { key in
                            LabeledContent(key) { Text(details.labels[key] ?? "").font(.caption.monospaced()).textSelection(.enabled) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Recent logs, optionally followed live. Following is offered only when the local CLI's help lists `--follow`.
private struct ContainerLogs: View {
    @Environment(Store.self) private var store
    let container: ContainerRow
    @ViewState<Bool> private var follow = false
    @ViewState<Bool> private var canFollow = false
    @ViewState<String> private var text = ""
    @ViewState<UUID> private var source = UUID()
    @ViewState<Int> private var reloads = 0
    private struct Request: Hashable { let id: String; let follow: Bool; let reloads: Int }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Follow", isOn: $follow).toggleStyle(.switch).controlSize(.small).disabled(!canFollow)
                    .help(canFollow ? "Keep streaming new lines" : "This CLI version cannot follow logs")
                Spacer()
                Button { reloads += 1 } label: { Label("Reload", systemImage: "arrow.clockwise") }.help("Reload")
                Button { store.copy(text) } label: { Label("Copy", systemImage: "doc.on.doc") }.help("Copy logs")
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless)
            OutputPanel(text: text, source: source, placeholder: "No log output.")
        }
        .padding([.horizontal, .bottom], 12)
        .task(id: container.id) { canFollow = await store.supports(["logs"], flag: "--follow") }
        .task(id: Request(id: container.id, follow: follow, reloads: reloads)) { await load() }
    }
    private func load() async {
        text = ""; source = UUID()
        let (chunks, sink) = AsyncStream.makeStream(of: String.self)
        let reader = Task { for await chunk in chunks { text += chunk } }
        let command = store.config.nativeCommand(["logs", "-n", "500"] + (follow ? ["--follow"] : []) + [container.id])
        do { _ = try await Runner.run(command, timeout: follow ? 3600 : 30) { sink.yield($0) } }
        catch { if !Task.isCancelled { sink.yield("\n" + error.localizedDescription + "\n") } }
        sink.finish(); await reader.value
    }
}

private struct ContainerJSON: View {
    @Environment(Store.self) private var store
    let container: ContainerRow
    @ViewState<String> private var text = ""
    var body: some View {
        OutputPanel(text: text, source: container.id, followsEnd: false, placeholder: "Loading…")
            .padding([.horizontal, .bottom], 12)
            .task(id: container.id) {
                text = ""
                do { text = JSONText.pretty(try await store.read(["inspect", container.id])) } catch { text = error.localizedDescription }
            }
    }
}
