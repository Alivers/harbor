import SwiftUI
import AppKit
import HarborCore

/// The Run Container form. Lists are edited entry by entry, problems are explained inline, and the
/// container starts in the background as soon as the form is submitted.
struct RunContainerSheet: View {
    typealias Entry = EntryListEditor.Entry
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ViewState<RunOptions> private var options: RunOptions
    @ViewState<[Entry]> private var ports: [Entry]
    @ViewState<[Entry]> private var environment: [Entry]
    @ViewState<[Entry]> private var volumes: [Entry]
    @ViewState<[Entry]> private var labels: [Entry]
    /// Optional `container run` flags the local help lists; the form offers only those.
    @ViewState<Set<String>> private var supported: Set<String> = []
    @ViewState<[String]> private var networks: [String] = []
    @ViewState<[String]> private var namedVolumes: [String] = []
    private let cores = ProcessInfo.processInfo.activeProcessorCount

    init(options: RunOptions) {
        _options = ViewState(initialValue: options)
        _ports = ViewState(initialValue: options.ports.map { Entry(text: $0) })
        _environment = ViewState(initialValue: options.environment.map { Entry(text: $0) })
        _volumes = ViewState(initialValue: options.volumes.map { Entry(text: $0) })
        _labels = ViewState(initialValue: options.labels.map { Entry(text: $0) })
    }
    private var resolved: RunOptions {
        var result = options
        result.ports = ports.map(\.text); result.environment = environment.map(\.text); result.volumes = volumes.map(\.text)
        result.labels = labels.map(\.text)
        return result
    }
    private func offers(_ flag: String) -> Bool { supported.contains(flag) }

    var body: some View {
        let problem = resolved.problem
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("Image", text: $options.image, prompt: Text("nginx:alpine")).font(.body.monospaced())
                        if !store.images.isEmpty {
                            Menu {
                                ForEach(store.images) { image in Button(image.reference) { options.image = image.reference } }
                            } label: { Image(systemName: "square.3.layers.3d") }
                            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize().help("Choose a local image")
                        }
                    }
                    TextField("Name", text: $options.name, prompt: Text("Generated when empty"))
                    if offers("--network") {
                        Picker("Network", selection: $options.network) {
                            Text("Default").tag("")
                            ForEach(networks.filter { $0 != "default" }, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if offers("--arch") {
                        Picker("Architecture", selection: $options.architecture) {
                            Text("This Mac (arm64)").tag("")
                            Text("Intel (amd64)").tag("amd64")
                        }
                    }
                } header: { Text("Container") }
                Section {
                    EntryListEditor(entries: $ports, placeholder: "127.0.0.1:8080:80", addTitle: "Add Port")
                } header: { Text("Published Ports") } footer: { Text("Host port, then container port. Prefix 127.0.0.1: to keep it on this Mac.") }
                Section {
                    EntryListEditor(entries: $environment, placeholder: "KEY=value", addTitle: "Add Variable")
                } header: { Text("Environment") } footer: { Text("Values are passed literally; nothing is expanded.") }
                Section {
                    EntryListEditor(entries: $volumes, placeholder: "/host/path:/container/path or name:/path", addTitle: "Add Volume")
                    HStack(spacing: 16) {
                        Button { chooseFolder() } label: { Label("Mount a Folder…", systemImage: "folder.badge.plus") }
                        if !namedVolumes.isEmpty {
                            Menu {
                                ForEach(namedVolumes, id: \.self) { name in
                                    Button(name) { withAnimation(.smooth) { volumes.append(Entry(text: name + ":/data")) } }
                                }
                            } label: { Label("Use a Named Volume", systemImage: "externaldrive.badge.plus") }
                            .menuStyle(.button).fixedSize()
                        }
                    }
                    .buttonStyle(.borderless)
                } header: { Text("Volumes") } footer: { Text("Change the path after the colon to where the data belongs inside the container.") }
                Section {
                    Stepper("CPUs: \(options.cpus)", value: $options.cpus, in: 1...max(cores, 1))
                    TextField("Memory", text: $options.memory, prompt: Text("1g"))
                } header: { Text("Resources") }
                if offers("--rm") || offers("--init") || offers("--read-only") {
                    Section {
                        if offers("--rm") { Toggle("Delete the container when it stops", isOn: $options.removeWhenStopped) }
                        if offers("--init") { Toggle("Run an init process (forwards signals, reaps zombies)", isOn: $options.useInit) }
                        if offers("--read-only") { Toggle("Read-only root filesystem", isOn: $options.readOnly) }
                    } header: { Text("Behavior") }
                }
                Section {
                    TextField("Command", text: $options.command, prompt: Text("Image default")).font(.body.monospaced())
                    if offers("--entrypoint") { TextField("Entrypoint", text: $options.entrypoint, prompt: Text("Image default")).font(.body.monospaced()) }
                    if offers("--workdir") { TextField("Working directory", text: $options.workingDirectory, prompt: Text("Image default, e.g. /app")).font(.body.monospaced()) }
                    if offers("--user") { TextField("User", text: $options.user, prompt: Text("Image default, e.g. 1000:1000")).font(.body.monospaced()) }
                } header: { Text("Process") }
                if offers("--label") {
                    Section {
                        EntryListEditor(entries: $labels, placeholder: "key=value", addTitle: "Add Label")
                    } header: { Text("Labels") }
                }
                Section {
                    TextField("Extra arguments", text: $options.extraOptions, prompt: Text("--dns 1.1.1.1")).font(.body.monospaced())
                } header: { Text("Advanced") } footer: { Text("Any other `container run` option. Quotes group words; there is no shell expansion.") }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 12) {
                if !store.engine.isRunning {
                    Label("Start the engine first.", systemImage: "power").foregroundStyle(.secondary)
                } else if let problem, !options.image.isEmpty {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
                        .transition(.opacity)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Run") { submit() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(problem != nil || !store.engine.isRunning)
            }
            .font(.callout)
            .padding(16)
            .animation(.smooth, value: problem)
        }
        .frame(width: 600, height: 720)
        .task {
            if let help = await store.help(for: ["run"]) { supported = Set(RunOptions.optionalFlags.filter { help.contains($0) }) }
            networks = await store.names(["network", "list"])
            namedVolumes = await store.names(["volume", "list"])
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.title = "Choose a Folder to Mount"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        withAnimation(.smooth) { volumes.append(Entry(text: url.path + ":/mnt/" + url.lastPathComponent)) }
    }
    private func submit() {
        guard (try? store.runContainer(resolved)) != nil else { return }
        dismiss()
    }
}
