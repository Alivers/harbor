import SwiftUI
import AppKit
import UniformTypeIdentifiers
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
        if !ImageReference.isNewName(trimmed) { return "Enter a new name, like registry.example.com/team/app:1.0." }
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

/// Commit to Image: a new image from a container's root filesystem (`container commit`, 1.6.0).
struct CommitContainerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let container: ContainerRow
    @ViewState<String> private var reference = ""
    private var trimmed: String { reference.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Commit to Image", systemImage: "square.and.arrow.down.on.square").font(.title2.weight(.semibold))
            LabeledContent("Container") { Text(container.name).font(.body.monospaced()).textSelection(.enabled) }
            TextField("Image name", text: $reference, prompt: Text("local/web:snapshot"))
                .textFieldStyle(.roundedBorder).font(.body.monospaced())
            Text((container.running ? "The container keeps running; the CLI takes a snapshot of it first. " : "")
                 + "The image holds the container's own files; volumes and mounted folders are not part of it. It starts the container's command unless you give another.")
                .font(.callout).foregroundStyle(.secondary)
            SheetFooter(problem: ContainerCommit.problem(trimmed), action: "Commit") {
                guard (try? store.commit(container, as: trimmed)) != nil else { return }
                dismiss()
            }
            .padding(-16)
        }
        .padding(24).frame(width: 520)
        .onAppear { reference = ContainerCommit.suggestedReference(for: container.name) }
    }
}

/// Create Cluster: a local Kubernetes cluster from the experimental `cluster` plugin, optionally with worker nodes.
struct CreateClusterSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ViewState<ClusterOptions> private var options = ClusterOptions()
    /// The local `cluster create --help`; options in `ClusterOptions.optionalFlags` show only when it lists them.
    @ViewState<String?> private var help: String?
    @ViewState<Bool> private var helpRead = false
    private let cores = ProcessInfo.processInfo.activeProcessorCount
    private func offers(_ flag: String) -> Bool { help?.contains(flag) ?? false }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $options.name, prompt: Text(KubernetesPlugin.defaultCluster(plugin: store.clusterPlugin)))
                    if offers("--workers") {
                        Stepper(options.workers == 0 ? "Workers: none" : "Workers: \(options.workers)", value: $options.workers, in: 0...ClusterOptions.maxWorkers)
                    }
                } header: { Text("Cluster") } footer: {
                    if offers("--workers") {
                        Text("With no workers, the control-plane node runs pods too. Workers are named \(options.name)-worker-1, -2… and get the same CPUs and memory.")
                    }
                }
                Section {
                    Stepper(options.cpus == 0 ? "CPUs: default" : "CPUs: \(options.cpus)", value: $options.cpus, in: 0...max(cores, 1))
                    TextField("Memory", text: $options.memory, prompt: Text("Default, or e.g. 8g"))
                } header: { Text("Each Node") } footer: { Text("By default a node gets a quarter of this Mac's cores and memory, at least 2 CPUs and 2 GB.") }
                Section {
                    Picker("Network plugin", selection: $options.network) {
                        Text("Bundled (kindnet)").tag(ClusterOptions.Network.bundled)
                        if offers("NONE") { Text("None").tag(ClusterOptions.Network.none) }
                        Text("From a Manifest File").tag(ClusterOptions.Network.manifest)
                    }
                    if options.network == .manifest {
                        LabeledContent("Manifest") {
                            HStack {
                                Text(options.manifest.isEmpty ? "None" : options.manifest).lineLimit(1).truncationMode(.middle)
                                    .foregroundStyle(options.manifest.isEmpty ? .secondary : .primary)
                                Button("Choose…", action: chooseManifest)
                            }
                        }
                    }
                } header: { Text("Pod Network") } footer: {
                    if options.network == .none { Text("Nodes stay Not Ready until you apply a network plugin with kubectl apply.") }
                }
                Section {
                    TextField("Node image", text: $options.nodeImage, prompt: Text("The CLI's kindest/node image")).font(.body.monospaced())
                    if offers("--rm") { Toggle("Delete the cluster when it stops", isOn: $options.removeWhenStopped) }
                } header: { Text("Advanced") }
            }
            .formStyle(.grouped)
            Divider()
            SheetFooter(problem: problem, action: "Create") {
                guard (try? store.createCluster(options)) != nil else { return }
                dismiss()
            }
        }
        .frame(width: 560, height: 640)
        .task {
            // Start from the CLI's own default name, which 1.6.1 changed from k8s-dev to cluster-dev.
            if options.name == ClusterOptions().name { options.name = KubernetesPlugin.defaultCluster(plugin: store.clusterPlugin) }
            help = await store.help(for: ["cluster", "create"]); helpRead = true
        }
    }
    private var problem: String? {
        if !store.engine.isRunning { return "Start the engine first." }
        if helpRead && help == nil { return "The Kubernetes plugin did not answer. Check that it is installed, then reopen this form." }
        return options.problem
    }
    private func chooseManifest() {
        let panel = NSOpenPanel(); panel.title = "Choose a CNI Manifest"
        panel.canChooseDirectories = false; panel.allowedContentTypes = [.yaml, .json]
        if panel.runModal() == .OK, let url = panel.url { options.manifest = url.path }
    }
}

/// Load into Cluster: copies a local image into a Kubernetes cluster's nodes, so pods can use it without a registry.
struct LoadIntoClusterSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let image: ImageRow
    @ViewState<[KubernetesClusters.Cluster]?> private var clusters: [KubernetesClusters.Cluster]?
    @ViewState<String> private var cluster = ""
    /// Nodes to load into; empty means every node.
    @ViewState<Set<String>> private var nodes: Set<String> = []
    @ViewState<Bool> private var canPickNodes = false
    @ViewState<String?> private var failure: String?
    private var chosen: KubernetesClusters.Cluster? { clusters?.first { $0.name == cluster } }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Image") { Text(image.reference).font(.body.monospaced()).textSelection(.enabled) }
                    if let clusters, !clusters.isEmpty {
                        Picker("Cluster", selection: $cluster) { ForEach(clusters, id: \.name) { Text($0.name).tag($0.name) } }
                    } else if let failure {
                        Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(4)
                    } else if clusters != nil {
                        Text("No clusters yet. Create one on the Kubernetes page.").foregroundStyle(.secondary)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } footer: { Text("Pods can then use the image with imagePullPolicy: Never or IfNotPresent.") }
                if canPickNodes, let chosen, chosen.nodes.count > 1 {
                    Section {
                        ForEach(chosen.nodes, id: \.self) { node in
                            Toggle(node, isOn: Binding(get: { nodes.contains(node) }, set: { if $0 { nodes.insert(node) } else { nodes.remove(node) } }))
                        }
                    } header: { Text("Nodes") } footer: { Text(nodes.isEmpty ? "Every node gets the image." : "Only the chosen nodes get the image.") }
                }
            }
            .formStyle(.grouped)
            Divider()
            SheetFooter(problem: chosen == nil ? "Choose a cluster." : nil, action: "Load") {
                guard (try? store.load(image, into: cluster, nodes: chosen?.nodes.filter(nodes.contains) ?? [])) != nil else { return }
                dismiss()
            }
        }
        .frame(width: 520, height: 440)
        .onChange(of: cluster) { _, _ in nodes = [] }
        .task {
            canPickNodes = await store.supports(["cluster", "load-image"], flag: "--node")
            do {
                let found = KubernetesClusters.parse(try await store.read(["cluster", "list"]))
                clusters = found; cluster = found.first?.name ?? ""
            } catch { failure = error.localizedDescription; clusters = [] }
        }
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
