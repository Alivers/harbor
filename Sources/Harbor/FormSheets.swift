import SwiftUI
import AppKit
import HarborCore

/// Shared bottom bar for form sheets: the first problem on the left, Cancel and the action on the right.
private struct SheetFooter: View {
    @Environment(\.dismiss) private var dismiss
    let problem: String?
    let action: String
    let perform: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2).transition(.opacity)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(action, action: perform).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(problem != nil)
        }
        .font(.callout)
        .padding(16)
        .animation(.smooth, value: problem)
    }
}

/// Build Image: context folder, Dockerfile, tags and build arguments → `container build`.
struct BuildImageSheet: View {
    typealias Entry = EntryListEditor.Entry
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ViewState<BuildOptions> private var options: BuildOptions
    @ViewState<[Entry]> private var tags: [Entry]
    @ViewState<[Entry]> private var buildArgs: [Entry] = []
    init(options: BuildOptions) {
        _options = ViewState(initialValue: options)
        let suggested = options.context.isEmpty ? "" : "local/" + URL(fileURLWithPath: options.context).lastPathComponent.lowercased() + ":dev"
        _tags = ViewState(initialValue: [Entry(text: options.tags.first ?? suggested)])
    }
    private var resolved: BuildOptions {
        var result = options
        result.tags = tags.map(\.text); result.buildArgs = buildArgs.map(\.text)
        return result
    }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Context") {
                        HStack {
                            Text(options.context.isEmpty ? "None" : options.context).foregroundStyle(options.context.isEmpty ? .secondary : .primary)
                                .lineLimit(1).truncationMode(.middle)
                            Button("Choose…") { choose(folder: true) }
                        }
                    }
                    LabeledContent("Dockerfile") {
                        HStack {
                            Text(options.dockerfile.isEmpty ? "Dockerfile or Containerfile in the context" : options.dockerfile)
                                .foregroundStyle(options.dockerfile.isEmpty ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
                            if !options.dockerfile.isEmpty { Button("Clear") { options.dockerfile = "" } }
                            Button("Choose…") { choose(folder: false) }
                        }
                    }
                } header: { Text("Source") } footer: { Text("You can also drop a folder or a Dockerfile onto the Harbor window.") }
                Section {
                    EntryListEditor(entries: $tags, placeholder: "local/app:dev", addTitle: "Add Tag")
                } header: { Text("Tags") }
                Section {
                    EntryListEditor(entries: $buildArgs, placeholder: "KEY=value", addTitle: "Add Build Argument")
                } header: { Text("Build Arguments") }
                Section {
                    TextField("Target stage", text: $options.target, prompt: Text("Last stage"))
                    Picker("Platform", selection: $options.platform) {
                        Text("This Mac (linux/arm64)").tag("")
                        Text("linux/amd64").tag("linux/amd64")
                    }
                    Toggle("Pull newer base images", isOn: $options.pull)
                    Toggle("Build without cache", isOn: $options.noCache)
                } header: { Text("Options") }
            }
            .formStyle(.grouped)
            Divider()
            SheetFooter(problem: store.engine.isRunning ? resolved.problem : "Start the engine first.", action: "Build") {
                guard (try? store.build(resolved)) != nil else { return }
                dismiss()
            }
        }
        .frame(width: 600, height: 640)
    }
    private func choose(folder: Bool) {
        let panel = NSOpenPanel()
        panel.title = folder ? "Choose the Build Context" : "Choose a Dockerfile"
        panel.canChooseDirectories = folder; panel.canChooseFiles = !folder
        if !options.context.isEmpty { panel.directoryURL = URL(fileURLWithPath: options.context) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if folder {
            options.context = url.path
            if tags.allSatisfy({ $0.text.isEmpty }) { tags = [Entry(text: "local/" + url.lastPathComponent.lowercased() + ":dev")] }
        } else {
            options.dockerfile = url.path
            if options.context.isEmpty { options.context = url.deletingLastPathComponent().path }
        }
    }
}

/// Tag Image: a second name for an existing image, for example before pushing to a registry.
struct TagImageSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let image: ImageRow
    @ViewState<String> private var target = ""
    private var trimmed: String { target.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var problem: String? {
        if !ImageReference.isValid(trimmed) || trimmed.hasSuffix(":") || trimmed.hasSuffix("/") { return "Enter a new name, like registry.example.com/team/app:1.0." }
        if trimmed == image.reference { return "The new name is the same as the current one." }
        return nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Tag Image", systemImage: "tag").font(.title2.weight(.semibold))
            LabeledContent("Image") { Text(image.reference).font(.body.monospaced()).textSelection(.enabled) }
            TextField("New name", text: $target, prompt: Text("registry.example.com/team/app:1.0"))
                .textFieldStyle(.roundedBorder).font(.body.monospaced())
            Text("The image keeps its current name too. Push the new name to publish it.").font(.callout).foregroundStyle(.secondary)
            SheetFooter(problem: target.isEmpty ? nil : problem, action: "Tag") {
                guard problem == nil else { return }
                store.tag(image, as: trimmed); dismiss()
            }
            .padding(-16)
        }
        .padding(24).frame(width: 520)
        .onAppear { target = image.repository + ":" }
    }
}

struct CreateNetworkSheet: View {
    typealias Entry = EntryListEditor.Entry
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ViewState<NetworkOptions> private var options = NetworkOptions()
    @ViewState<[Entry]> private var labels: [Entry] = []
    private var resolved: NetworkOptions { var result = options; result.labels = labels.map(\.text); return result }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $options.name, prompt: Text("dev-net"))
                    TextField("Subnet", text: $options.subnet, prompt: Text("Automatic, or e.g. 192.168.100.0/24"))
                    Toggle("Host-only (no internet access)", isOn: $options.hostOnly)
                } header: { Text("Network") } footer: { Text("Containers on the same network reach each other by name. Pick it in the Run Container form.") }
                Section { EntryListEditor(entries: $labels, placeholder: "key=value", addTitle: "Add Label") } header: { Text("Labels") }
            }
            .formStyle(.grouped)
            Divider()
            SheetFooter(problem: options.name.isEmpty ? "Enter a name." : resolved.problem, action: "Create") {
                guard (try? store.createNetwork(resolved)) != nil else { return }
                dismiss()
            }
        }
        .frame(width: 520, height: 420)
    }
}

struct CreateVolumeSheet: View {
    typealias Entry = EntryListEditor.Entry
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ViewState<VolumeOptions> private var options = VolumeOptions()
    @ViewState<[Entry]> private var labels: [Entry] = []
    private var resolved: VolumeOptions { var result = options; result.labels = labels.map(\.text); return result }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $options.name, prompt: Text("app-data"))
                    TextField("Size", text: $options.size, prompt: Text("Default, or e.g. 10g"))
                } header: { Text("Volume") } footer: { Text("Volumes keep data when containers are deleted. Mount one in the Run Container form with “Use a Named Volume”.") }
                Section { EntryListEditor(entries: $labels, placeholder: "key=value", addTitle: "Add Label") } header: { Text("Labels") }
            }
            .formStyle(.grouped)
            Divider()
            SheetFooter(problem: options.name.isEmpty ? "Enter a name." : resolved.problem, action: "Create") {
                guard (try? store.createVolume(resolved)) != nil else { return }
                dismiss()
            }
        }
        .frame(width: 520, height: 400)
    }
}

/// Import Images: pick another Docker engine, choose images, copy them into Apple Container.
struct ImportImagesSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ViewState<[DockerImport.Source]> private var sources: [DockerImport.Source] = []
    @ViewState<String> private var sourceID = ""
    @ViewState<[DockerImport.Image]> private var images: [DockerImport.Image] = []
    @ViewState<Set<String>> private var selection: Set<String> = []
    @ViewState<String?> private var failure: String?
    @ViewState<Bool> private var loading = false
    private var source: DockerImport.Source? { sources.first { $0.id == sourceID } }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Import Images from Docker", systemImage: "square.and.arrow.down.on.square").font(.title2.weight(.semibold))
                Text("Copies images from OrbStack, Docker Desktop or another engine into Apple Container. The other engine is only read; nothing there changes.")
                    .font(.callout).foregroundStyle(.secondary)
                if sources.isEmpty {
                    Label("No Docker engine socket found. Start OrbStack, Docker Desktop or Colima, then reopen this sheet.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Picker("Engine", selection: $sourceID) {
                        ForEach(sources) { Text("\($0.name) — \($0.socket)").tag($0.id) }
                    }
                }
            }
            .padding(20)
            Group {
                if sources.isEmpty {
                    Spacer()
                } else if let failure {
                    ContentUnavailableView { Label("Could Not Read Images", systemImage: "exclamationmark.triangle") } description: { Text(failure).textSelection(.enabled) }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if images.isEmpty {
                    ContentUnavailableView("No Tagged Images", systemImage: "square.3.layers.3d", description: Text("Only images with a name and tag can be imported."))
                } else {
                    List(images, selection: $selection) { image in
                        HStack {
                            Text(image.reference).font(.body.monospaced()).lineLimit(1)
                            Spacer()
                            if store.images.contains(where: { ImageReference.sameImage($0.reference, image.reference) }) {
                                Text("Already here").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(image.size).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            SheetFooter(problem: !store.engine.isRunning ? "Start the engine first." : selection.isEmpty ? "Select the images to import." : nil,
                        action: selection.count > 1 ? "Import \(selection.count) Images" : "Import") {
                guard let source else { return }
                store.importImages(images.filter { selection.contains($0.id) }, from: source)
                dismiss()
            }
        }
        .frame(width: 640, height: 520)
        .task {
            sources = DockerImport.availableSources()
            sourceID = sources.first?.id ?? ""
        }
        .task(id: sourceID) { await load() }
    }
    private func load() async {
        guard let source else { return }
        loading = true; failure = nil; selection = []
        do { images = try await store.dockerImages(at: source) } catch { failure = error.localizedDescription; images = [] }
        loading = false
    }
}
