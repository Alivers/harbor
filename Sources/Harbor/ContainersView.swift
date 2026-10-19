import SwiftUI
import HarborCore

enum ContainerFilter: String, CaseIterable, Identifiable {
    case all = "All", running = "Running", stopped = "Stopped"
    var id: String { rawValue }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case overview = "Overview", logs = "Logs", inspect = "Inspect"
    var id: String { rawValue }
}

struct ContainersView: View {
    @Environment(Store.self) private var store
    @ViewState<String> private var search = ""
    @ViewState<ContainerFilter> private var filter: ContainerFilter = .all
    @ViewState<String?> private var selection: String?
    @ViewState<Bool> private var showInspector = false
    @ViewState<InspectorTab> private var tab: InspectorTab = .overview
    @ViewState<ContainerRow?> private var pendingDelete: ContainerRow?

    private var rows: [ContainerRow] {
        store.containers.filter { c in
            (filter == .all || c.running == (filter == .running))
                && (search.isEmpty || (c.name + " " + c.image).localizedCaseInsensitiveContains(search))
        }
    }
    private var selected: ContainerRow? { store.containers.first { $0.id == selection } }

    var body: some View {
        content
            .navigationTitle("Containers")
            .navigationSubtitle(subtitle)
            .searchable(text: $search, placement: .toolbar, prompt: "Name or image")
            .toolbar { toolbar }
            .inspector(isPresented: $showInspector) {
                ContainerInspector(container: selected, tab: $tab, onDelete: { pendingDelete = $0 })
                    .inspectorColumnWidth(min: 300, ideal: 380, max: 560)
            }
            .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { c in
                Button(c.running ? "Stop and Delete" : "Delete", role: .destructive) { store.delete(c) }
            } message: { _ in Text("The container's writable layer is removed. Images and volumes are kept.") }
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
                if let c = store.containers.first(where: { ids.contains($0.id) }) { menu(for: c) }
            } primaryAction: { ids in
                selection = ids.first; tab = .overview; showInspector = true
            }
            .animation(.smooth, value: rows)
        }
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
        Button("Show Logs") { selection = c.id; tab = .logs; showInspector = true }
        Button("Show Details") { selection = c.id; tab = .overview; showInspector = true }
        Button("Show Stats") { store.perform("Stats for \(c.name)", command: store.config.nativeCommand(["stats", "--no-stream", c.id]), showOutput: true) }
            .disabled(!c.running)
        ForEach(c.portMappings.compactMap(\.url), id: \.self) { url in Link("Open \(url.host() ?? ""):\(url.port ?? 0)", destination: url) }
        Button("Copy ID") { store.copy(c.id) }
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = c }.disabled(busy)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Show", selection: $filter) { ForEach(ContainerFilter.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).fixedSize()
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
                case .inspect: ContainerJSON(container: container)
                }
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.trailing", description: Text("Select a container to see its details and logs."))
        }
    }
}

private struct ContainerOverview: View {
    @Environment(Store.self) private var store
    let container: ContainerRow
    let onDelete: (ContainerRow) -> Void
    var body: some View {
        let busy = store.isBusy(container.id)
        Form {
            Section {
                LabeledContent("State") { StateBadge(state: container.state, running: container.running) }
                LabeledContent("Image") { Text(container.image).textSelection(.enabled) }
                LabeledContent("Resources") { Text(container.status).textSelection(.enabled) }
                LabeledContent("Ports") {
                    if container.portMappings.isEmpty { Text("None").foregroundStyle(.secondary) }
                    else { VStack(alignment: .trailing, spacing: 4) { PortLinks(mappings: container.portMappings, limit: 8) } }
                }
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
