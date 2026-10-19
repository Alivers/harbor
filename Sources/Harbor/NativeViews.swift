import SwiftUI
import AppKit
import HarborCore

extension Page {
    /// The read-only listing at the top of a generic resource page.
    var listing: [String] { switch self {
    case .build: ["builder", "status"]; case .networks: ["network", "list"]; case .volumes: ["volume", "list"]
    case .machines: ["machine", "list"]; case .kubernetes: ["k8s", "list"]; case .registries: ["registry", "list"]
    default: []
    } }
    /// Catalog commands that act on one listed resource, named by the table's first column.
    /// Each one's example must end with the resource name (see `NativeOperation.example(naming:)`).
    var rowActions: [String] { switch self {
    case .networks: ["network inspect", "network delete"]
    case .volumes: ["volume inspect", "volume delete"]
    case .machines: ["machine inspect", "machine logs", "machine set-default", "machine stop", "machine delete"]
    case .kubernetes: ["k8s write-config", "k8s delete"]
    case .registries: ["registry logout"]
    default: []
    } }
    var note: String? { switch self {
    case .kubernetes: "Kubernetes is an experimental plugin. Creating a cluster pulls node images and merges ~/.kube/config. There is no k8s start; Harbor never creates clusters on its own."
    case .machines: "Machine creation controls the home directory mount. The example uses --home-mount none; choose read-only or read-write sharing as needed."
    default: nil
    } }
}

extension Page {
    /// The page's own create form, opened from its toolbar.
    var createAction: (title: String, route: SheetRoute)? {
        switch self {
        case .networks: ("Create Network", .createNetwork)
        case .volumes: ("Create Volume", .createVolume)
        case .build: ("Build Image", .build(BuildOptions()))
        default: nil
        }
    }
}

extension NativeOperation {
    var symbol: String { switch path.last ?? "" {
    case "list", "df": "list.bullet"; case "inspect", "status", "version", "property": "info.circle"
    case "create", "run": "plus.circle"; case "delete", "prune", "clean": "trash"
    case "start": "play.circle"; case "stop", "kill": "stop.circle"; case "logs": "text.alignleft"
    case "login": "person.badge.key"; case "logout": "rectangle.portrait.and.arrow.right"
    case "pull", "load", "load-image": "arrow.down.circle"; case "push", "save", "export": "arrow.up.circle"
    case "build": "hammer"; case "exec": "terminal"; case "copy": "doc.on.doc"; case "tag": "tag"
    default: "chevron.left.forwardslash.chevron.right"
    } }
}

/// A raw CLI listing (parsed into a table when it is aligned) plus the page's catalog actions.
struct ResourceView: View {
    @Environment(Store.self) private var store
    let page: Page
    @ViewState<String> private var output = ""
    @ViewState<String?> private var failure: String?
    @ViewState<Bool> private var loaded = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                listing
                VStack(alignment: .leading, spacing: 10) {
                    Text("Actions").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                        ForEach(NativeOperation.operations(in: page.group ?? "")) { OperationTile(operation: $0) }
                    }
                }
                if let note = page.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(20)
        }
        .navigationTitle(page.title)
        .navigationSubtitle("container " + page.listing.joined(separator: " "))
        .toolbar {
            if let create = page.createAction {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.present(create.route) } label: { Label(create.title, systemImage: "plus") }
                        .disabled(!store.engine.isRunning).help(create.title)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Label("Reload", systemImage: "arrow.clockwise") }.help("Read the list again")
            }
            if let group = page.group { ToolbarItem(placement: .primaryAction) { NativeActionsMenu(group: group) } }
        }
        // Reload after any job finishes: it may have created or deleted what this page lists.
        .task(id: "\(store.changeCount) \(store.engine.isRunning)") { await load() }
    }
    @ViewBuilder private var listing: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled).lineLimit(6)
                Text("A stopped engine, an older CLI or a missing plugin can cause this.").font(.caption).foregroundStyle(.secondary)
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if let table = TextTable.parse(output) {
                if table.rows.isEmpty { Text("Nothing here yet.").foregroundStyle(.secondary) }
                else { ResourceTable(table: table, actions: page.rowActions.compactMap(NativeOperation.named), usedBy: usedBy) }
            } else {
                ScrollView(.horizontal) {
                    Text(output.isEmpty ? "No output." : output).font(.callout.monospaced()).textSelection(.enabled)
                }
            }
        }
        .card()
        .animation(.smooth, value: output)
    }
    /// Containers that use a listed network or volume, from their configuration; nil on other pages.
    private var usedBy: ((String) -> [String])? {
        let containers = store.containers
        switch page {
        case .volumes:
            return { name in containers.filter { c in c.details?.volumeNames.contains(name) == true }.map(\.name) }
        case .networks:
            return { name in containers.filter { c in c.details?.networks.contains { network in network.name == name } == true }.map(\.name) }
        default:
            return nil
        }
    }
    private func load() async {
        do { let text = try await store.read(page.listing, timeout: 15); if text != output { output = text }; failure = nil }
        catch { failure = error.localizedDescription }
        loaded = true
    }
}

private struct ResourceTable: View {
    @Environment(Store.self) private var store
    let table: TextTable
    let actions: [NativeOperation]
    var usedBy: ((String) -> [String])?
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            GridRow {
                ForEach(table.columns.indices, id: \.self) { i in
                    Text(table.columns[i].capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                if usedBy != nil { Text("Used By").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            Divider()
            ForEach(table.rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(table.columns.indices, id: \.self) { i in
                        Text(table.rows[r][i]).font(i == 0 ? Font.callout.weight(.medium) : Font.callout).lineLimit(1).textSelection(.enabled)
                    }
                    if let usedBy {
                        let names = usedBy(table.rows[r].first ?? "")
                        Text(names.isEmpty ? "—" : names.joined(separator: ", ")).font(.callout).foregroundStyle(names.isEmpty ? .tertiary : .secondary)
                            .lineLimit(1).help(names.joined(separator: ", "))
                    }
                    if !actions.isEmpty, let name = table.rows[r].first, !name.isEmpty {
                        Menu {
                            ForEach(actions) { op in
                                Button(op.title) { store.present(.operation(NativeRequest(op, arguments: op.example(naming: name)))) }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                        .help("Actions for \(name)")
                    }
                }
            }
        }
    }
}

struct OperationTile: View {
    @Environment(Store.self) private var store
    let operation: NativeOperation
    @ViewState<Bool> private var hovering = false
    var body: some View {
        Button { store.present(.operation(NativeRequest(operation))) } label: {
            HStack(spacing: 10) {
                Image(systemName: operation.symbol).foregroundStyle(operation.destructive ? Color.red : Color.harbor).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.title).font(.callout.weight(.medium))
                    Text("container " + operation.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if operation.admin { Image(systemName: "lock").foregroundStyle(.secondary).help("Asks for an administrator password in Terminal") }
                else if operation.terminal { Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary).help("Opens in Terminal") }
            }
            .padding(12)
            .background(Color.primary.opacity(hovering ? 0.08 : 0.04), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Toolbar menu with every catalog command of a group.
struct NativeActionsMenu: View {
    @Environment(Store.self) private var store
    let group: String
    var body: some View {
        Menu {
            ForEach(NativeOperation.operations(in: group)) { op in
                Button(op.title) { store.present(.operation(NativeRequest(op))) }
            }
        } label: { Label("Native Actions", systemImage: "ellipsis.circle") }
        .help("All native \(group.lowercased()) commands")
    }
}

struct CatalogView: View {
    @Environment(Store.self) private var store
    @ViewState<String> private var search = ""
    @ViewState<String> private var custom = ""
    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Text("container").font(.body.monospaced()).foregroundStyle(.secondary)
                    TextField("Arguments", text: $custom, prompt: Text("system status")).textFieldStyle(.plain).font(.body.monospaced()).onSubmit(openCustom)
                    Button("Open", action: openCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Custom Command") } footer: {
                Text("Quotes group words; there are no pipes, redirects or expansion. Harbor shows the local help before anything runs.")
            }
            ForEach(NativeOperation.groups, id: \.self) { group in
                let ops = NativeOperation.operations(in: group).filter { search.isEmpty || ($0.title + " " + $0.id + " " + group).localizedCaseInsensitiveContains(search) }
                if !ops.isEmpty {
                    Section(group) { ForEach(ops) { CatalogRow(operation: $0) } }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Commands")
        .navigationTitle("All Commands")
        .navigationSubtitle("\(NativeOperation.all.count) native commands")
    }
    private func openCustom() {
        let text = custom.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.present(.operation(NativeRequest(NativeOperation("Custom", "Custom Command", "", text))))
    }
}

private struct CatalogRow: View {
    @Environment(Store.self) private var store
    let operation: NativeOperation
    var body: some View {
        Button { store.present(.operation(NativeRequest(operation))) } label: {
            HStack(spacing: 10) {
                Image(systemName: operation.symbol).foregroundStyle(operation.destructive ? Color.red : Color.harbor).frame(width: 20)
                Text(operation.title)
                Spacer()
                Text("container " + operation.id).font(.callout.monospaced()).foregroundStyle(.secondary)
                if operation.admin { Image(systemName: "lock").foregroundStyle(.secondary) }
                else if operation.terminal { Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Edit a native command's arguments, check them against the local help, then run it.
/// Running stays disabled until the help is confirmed to belong to this subcommand.
struct NativeOperationSheet: View {
    enum HelpState { case loading, verified, unavailable }
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: NativeRequest
    @ViewState<String> private var arguments = ""
    @ViewState<String> private var directory = ""
    @ViewState<String> private var help = ""
    @ViewState<HelpState> private var helpState: HelpState = .loading
    @ViewState<Bool> private var terminal = false
    @ViewState<Bool> private var confirm = false
    @ViewState<String?> private var validation: String?
    private var operation: NativeOperation { request.operation }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(operation.title).font(.title2.weight(.semibold))
                    Text("container " + operation.id).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                helpBadge
            }
            TextField("Arguments", text: $arguments, prompt: Text("Arguments"), axis: .vertical)
                .lineLimit(2...4).font(.body.monospaced()).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Working directory", text: $directory, prompt: Text("Working directory (optional)")).textFieldStyle(.roundedBorder)
                Button("Choose…", action: chooseDirectory)
            }
            Toggle("Run in Terminal, for interactive input or logs that never end", isOn: $terminal).disabled(operation.terminal)
            notes
            if let validation {
                Label(validation, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
            OutputPanel(text: help, source: operation.id, followsEnd: false, placeholder: "Reading local help…")
            HStack {
                Button("Copy Command", action: copyCommand)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(terminal ? "Open in Terminal" : "Run", action: attempt)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(helpState != .verified)
            }
        }
        .padding(22)
        .frame(width: 760, height: 640)
        .task { arguments = request.arguments; terminal = operation.terminal; await loadHelp() }
        .confirmationDialog("Run “\(operation.title)”?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Run", role: .destructive, action: execute)
        } message: { Text("This stops services or deletes resources. Check the names in the arguments.") }
        .animation(.smooth, value: validation)
    }

    @ViewBuilder private var helpBadge: some View {
        switch helpState {
        case .loading:
            ProgressView().controlSize(.small)
        case .verified:
            Label("Help verified", systemImage: "checkmark.seal.fill").foregroundStyle(Color.harbor).font(.callout)
        case .unavailable:
            HStack(spacing: 8) {
                Label("Not available in this CLI", systemImage: "xmark.seal").foregroundStyle(.orange).font(.callout)
                Button { Task { await loadHelp() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Read the help again")
            }
        }
    }
    @ViewBuilder private var notes: some View {
        if operation.admin {
            Label("Runs with sudo in Terminal, where macOS asks for your password. Harbor never sees it.", systemImage: "lock")
                .font(.callout).foregroundStyle(.secondary)
        }
        if operation.path == ["k8s", "create"] || operation.path == ["k8s", "write-config"] {
            Label("Updates your kubeconfig as the official CLI does; check the cluster name.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    private func loadHelp() async {
        helpState = .loading; help = ""
        do {
            let text = try await store.read(operation.path + ["--help"], timeout: 10)
            if NativeHelp.matches(text, path: operation.path) { help = text; helpState = .verified }
            else { help = "The CLI did not return help for this command. Check the version, engine status or plugins.\n\n" + text; helpState = .unavailable }
        } catch {
            help = error.localizedDescription + "\n\nCould not read help for this command. Check the CLI path, version and plugins."
            helpState = .unavailable
        }
    }
    private func makeCommand() throws -> Command {
        var command = store.config.nativeCommand(operation.path + (try ArgumentTokenizer.split(arguments)))
        guard !command.arguments.isEmpty else { throw HarborError.message("Enter a subcommand, for example: system status") }
        let folder = directory.trimmingCharacters(in: .whitespaces)
        if !folder.isEmpty {
            var isDirectory: ObjCBool = false
            guard folder.hasPrefix("/"), FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw HarborError.message("The working directory must be an existing folder, given as an absolute path.")
            }
            command.directory = folder
        }
        return command
    }
    private func copyCommand() {
        do { store.copy(TerminalScript.shellLine(try makeCommand(), admin: operation.admin)); validation = nil }
        catch { validation = error.localizedDescription }
    }
    private func attempt() {
        do { _ = try makeCommand(); validation = nil } catch { validation = error.localizedDescription; return }
        if operation.destructive { confirm = true } else { execute() }
    }
    private func execute() {
        guard let command = try? makeCommand() else { return }
        if terminal {
            dismiss()
            store.openInTerminal(command, admin: operation.admin, title: operation.title)
        } else {
            // Replaces this sheet with the job's output.
            store.perform(operation.title, command: command, showOutput: true, timeout: 1800)
        }
    }
    private func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { directory = url.path }
    }
}
