import SwiftUI
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
    private let cores = ProcessInfo.processInfo.activeProcessorCount

    init(options: RunOptions) {
        _options = ViewState(initialValue: options)
        _ports = ViewState(initialValue: options.ports.map { Entry(text: $0) })
        _environment = ViewState(initialValue: options.environment.map { Entry(text: $0) })
        _volumes = ViewState(initialValue: options.volumes.map { Entry(text: $0) })
    }
    private var resolved: RunOptions {
        var result = options
        result.ports = ports.map(\.text); result.environment = environment.map(\.text); result.volumes = volumes.map(\.text)
        return result
    }

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
                } header: { Text("Container") }
                Section {
                    EntryListEditor(entries: $ports, placeholder: "127.0.0.1:8080:80", addTitle: "Add Port")
                } header: { Text("Published Ports") } footer: { Text("Host port, then container port. Prefix 127.0.0.1: to keep it on this Mac.") }
                Section {
                    EntryListEditor(entries: $environment, placeholder: "KEY=value", addTitle: "Add Variable")
                } header: { Text("Environment") } footer: { Text("Values are passed literally; nothing is expanded.") }
                Section {
                    EntryListEditor(entries: $volumes, placeholder: "/host/path:/container/path", addTitle: "Add Volume")
                } header: { Text("Volumes") }
                Section {
                    Stepper("CPUs: \(options.cpus)", value: $options.cpus, in: 1...max(cores, 1))
                    TextField("Memory", text: $options.memory, prompt: Text("1g"))
                } header: { Text("Resources") }
                Section {
                    TextField("Extra arguments", text: $options.extraOptions, prompt: Text("--network dev-net")).font(.body.monospaced())
                    TextField("Command", text: $options.command, prompt: Text("Image default")).font(.body.monospaced())
                } header: { Text("Advanced") } footer: { Text("Any `container run` option. Quotes group words; there is no shell expansion.") }
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
        .frame(width: 580, height: 680)
    }
    private func submit() {
        guard (try? store.runContainer(resolved)) != nil else { return }
        dismiss()
    }
}
