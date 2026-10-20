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
        // The inspector is a pane of its own beside the page, as in the design; it slides in without
        // touching the sidebar.
        HStack(alignment: .top, spacing: 12) {
            PageScaffold(title: "Containers", subtitle: subtitle) { controls } content: { content }
            if showInspector {
                ContainerInspector(container: selected, selectionCount: selection.count, tab: $tab,
                                   onDelete: { pendingDelete = [$0] }, onClose: { showInspector = false })
                    .frame(width: 330)
                    .frame(maxHeight: .infinity)
                    .glassPanel()
                    // A slide only: fading would group the pane and drop its blur until the animation ends.
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.smooth(duration: 0.32), value: showInspector)
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

    @ViewBuilder private var controls: some View {
        GlassControls {
            GlassSearchField(text: $search, prompt: "Name or image")
            HeaderMenu(systemName: "arrow.up.arrow.down", help: "Sort containers") {
                Picker("Sort By", selection: $sort) { ForEach(ContainerSort.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.inline)
            }
            HeaderMenu(systemName: "ellipsis", help: "All native container commands") { NativeActionItems(group: "Containers") }
            Button(action: toggleInspector) { HeaderIcon(systemName: "sidebar.trailing") }
                .buttonStyle(.plain)
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("Show or hide details (⌥⌘I)")
                .accessibilityLabel("Details")
        }
        PrimaryActionButton(title: "Run Container (⌘N)") { store.present(.run(RunOptions())) }
            .disabled(!store.engine.isRunning)
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
            .huggingGlassPanel(height: 320)
        } else {
            // The filter lives in the pane, with the list it filters, as in the design.
            VStack(spacing: 0) {
                HStack {
                    PillPicker(selection: $filter, options: ContainerFilter.allCases)
                    Spacer()
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14))
                PaneDivider()
                if rows.isEmpty {
                    Group {
                        if search.isEmpty { ContentUnavailableView("No \(filter.rawValue) Containers", systemImage: "shippingbox") }
                        else { ContentUnavailableView.search(text: search) }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    SelectableRows(items: rows, selection: $selection, rowHeight: ContainerListRow.height,
                                   onOpen: { c in show(c, .overview) }, onDelete: { pendingDelete = $0 }) { c in
                        ContainerListRow(container: c)
                    } menu: { chosen in
                        if chosen.count == 1, let c = chosen.first { menu(for: c) }
                        else if !chosen.isEmpty { bulkMenu(for: chosen) }
                    }
                }
            }
            .huggingGlassPanel(height: rows.isEmpty ? 300 : 60 + CGFloat(rows.count) * ContainerListRow.height)
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
    /// Opening the details with nothing selected shows the first container rather than an empty pane.
    private func toggleInspector() {
        if !showInspector, selection.isEmpty, let first = rows.first { selection = [first.id] }
        showInspector.toggle()
    }
}

private struct ContainerListRow: View {
    static let height: CGFloat = 60
    @Environment(Store.self) private var store
    let container: ContainerRow
    @ViewState<Bool> private var hovering = false
    var body: some View {
        let busy = store.isBusy(container.id)
        HStack(spacing: 12) {
            RowIcon(systemName: "shippingbox", active: container.running)
                .symbolEffect(.pulse, isActive: busy)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(container.image).font(.system(size: 11)).foregroundStyle(Color.harborSub).lineLimit(1)
            }
            .frame(minWidth: 80, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 8)
            // Ports give way first when the inspector makes the list narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { PortLinks(mappings: container.portMappings, running: container.running); StateBadge(state: container.state, running: container.running) }
                StateBadge(state: container.state, running: container.running)
            }
            HStack(spacing: 2) {
                if busy {
                    ProgressView().controlSize(.small).frame(width: 24)
                } else {
                    Button { container.running ? store.stop(container) : store.start(container) } label: {
                        Image(systemName: container.running ? "stop.fill" : "play.fill").contentTransition(.symbolEffect(.replace))
                            .frame(width: 24, height: 24).contentShape(.rect)
                    }
                    .help(container.running ? "Stop" : "Start")
                    Button { store.openShell(container) } label: { Image(systemName: "terminal").frame(width: 24, height: 24).contentShape(.rect) }
                        .help("Open a shell in Terminal").disabled(!container.running)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.harborSub)
            .frame(width: 52, alignment: .trailing)
            .opacity(hovering || busy ? 1 : 0)
        }
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
    let onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(container?.name ?? "Details").font(.system(size: 15, weight: .bold)).lineLimit(1).textSelection(.enabled)
                    if let container {
                        Text("\(container.image) · \(container.state.capitalized)").font(.system(size: 11)).foregroundStyle(Color.harborSub).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22).contentShape(.circle) }
                    .buttonStyle(.plain).foregroundStyle(Color.harborSub).help("Hide details").accessibilityLabel("Hide details")
            }
            if let container {
                PillPicker(selection: $tab, options: InspectorTab.allCases, small: true)
                Group {
                    switch tab {
                    case .overview: ContainerOverview(container: container)
                    case .logs: ContainerLogs(container: container)
                    case .stats: ContainerStatsView(container: container)
                    case .files: ContainerFilesView(container: container)
                    case .inspect: ContainerJSON(container: container)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                actions(for: container)
            } else if selectionCount > 1 {
                ContentUnavailableView("\(selectionCount) Containers Selected", systemImage: "square.stack",
                                       description: Text("Right-click the selection to start, stop or delete them together."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.trailing", description: Text("Select a container to see its details and logs."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // The header stays at the top whatever the pane shows below it.
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
    }
    /// The design's small glass buttons at the foot of the pane.
    private func actions(for c: ContainerRow) -> some View {
        let busy = store.isBusy(c.id)
        return HStack(spacing: 8) {
            if c.running {
                Button("Stop") { store.stop(c) }.disabled(busy)
                Button("Restart") { store.restart(c) }.disabled(busy)
                Button("Open Shell") { store.openShell(c) }
            } else {
                Button("Start") { store.start(c) }.disabled(busy)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { onDelete(c) } label: { Image(systemName: "trash") }
                .disabled(busy).help("Delete…").accessibilityLabel("Delete")
        }
        .buttonStyle(MiniButtonStyle())
    }
}

private struct ContainerOverview: View {
    let container: ContainerRow
    @ViewState<Bool> private var showValues = false
    var body: some View {
        let details = container.details
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                InfoSection {
                    InfoRow("State") { StateBadge(state: container.state, running: container.running) }
                    InfoRow("Image") { Text(container.image).textSelection(.enabled) }
                    InfoRow("Resources") { Text(container.status).textSelection(.enabled) }
                    InfoRow("Ports") {
                        if container.portMappings.isEmpty { Text("None").foregroundStyle(Color.harborSub) }
                        else { VStack(alignment: .trailing, spacing: 4) { PortLinks(mappings: container.portMappings, limit: 8, running: container.running) } }
                    }
                    if let created = details?.created { InfoRow("Created") { Text(created, format: .relative(presentation: .named)) }.help(created.formatted()) }
                    if container.running, let started = details?.started { InfoRow("Started") { Text(started, format: .relative(presentation: .named)) }.help(started.formatted()) }
                    if let platform = details?.platform, !platform.isEmpty { InfoRow("Platform", text: platform) }
                    InfoRow("ID") { Text(container.id).font(.system(size: 11).monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
                }
                if let details {
                    if !details.command.isEmpty || !details.workingDirectory.isEmpty || !details.user.isEmpty {
                        InfoSection("Process") {
                            if !details.command.isEmpty { InfoRow("Command") { Text(details.command.map(Command.quote).joined(separator: " ")).font(.system(size: 11).monospaced()).textSelection(.enabled) } }
                            if !details.workingDirectory.isEmpty { InfoRow("Directory") { Text(details.workingDirectory).font(.system(size: 11).monospaced()).textSelection(.enabled) } }
                            if !details.user.isEmpty { InfoRow("User") { Text(details.user).font(.system(size: 11).monospaced()) } }
                        }
                    }
                    if !details.networks.isEmpty {
                        InfoSection("Networks") {
                            ForEach(details.networks, id: \.self) { network in
                                InfoRow(network.name) {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(network.address.isEmpty ? "Not connected" : network.address).font(.system(size: 11).monospaced()).textSelection(.enabled)
                                            .foregroundStyle(network.address.isEmpty ? Color.harborSub : Color.primary)
                                        if !network.hostname.isEmpty { Text(network.hostname).font(.system(size: 11)).foregroundStyle(Color.harborSub).textSelection(.enabled) }
                                    }
                                }
                            }
                        }
                    }
                    if !details.mounts.isEmpty {
                        InfoSection("Mounts") {
                            ForEach(details.mounts, id: \.self) { mount in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Image(systemName: mount.kind == "volume" ? "externaldrive" : mount.kind == "bind" ? "folder" : "memorychip")
                                            .foregroundStyle(Color.harborSub).accessibilityLabel(mount.kind)
                                        Text(mount.destination).font(.system(size: 12).monospaced())
                                        if mount.readOnly { Text("read-only").font(.system(size: 10)).foregroundStyle(Color.harborSub) }
                                    }
                                    Text(mount.kind == "tmpfs" ? "tmpfs" : mount.source).font(.system(size: 11).monospaced()).foregroundStyle(Color.harborSub)
                                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(mount.source)
                                }
                                .padding(.vertical, 4).padding(.horizontal, 2)
                            }
                        }
                    }
                    if !details.environment.isEmpty {
                        InfoSection(title: "Environment") {
                            ForEach(details.environment, id: \.self) { entry in
                                let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
                                InfoRow(parts.first ?? entry) {
                                    Text(showValues ? (parts.count > 1 ? parts[1] : "") : "••••••").font(.system(size: 11).monospaced())
                                        .lineLimit(3).textSelection(.enabled)
                                }
                            }
                        } accessory: {
                            Button(showValues ? "Hide Values" : "Show Values") { showValues.toggle() }
                                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.harborText)
                        }
                    }
                    if !details.labels.isEmpty {
                        InfoSection("Labels") {
                            ForEach(details.labels.keys.sorted(), id: \.self) { key in
                                InfoRow(key) { Text(details.labels[key] ?? "").font(.system(size: 11).monospaced()).textSelection(.enabled) }
                            }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.automatic)
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
            .task(id: container.id) {
                text = ""
                do { text = JSONText.pretty(try await store.read(["inspect", container.id])) } catch { text = error.localizedDescription }
            }
    }
}
