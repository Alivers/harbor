import SwiftUI
import HarborCore

struct ImagesView: View {
    @Environment(Store.self) private var store
    @ViewState<String> private var search = ""
    @ViewState<Set<String>> private var selection: Set<String> = []
    @ViewState<[ImageRow]> private var pendingDelete: [ImageRow] = []
    @ViewState<Bool?> private var pendingPrune: Bool?
    @ViewState<ImageRow?> private var pendingPush: ImageRow?
    /// Whether the k8s plugin can load images (it only answers while the engine runs).
    @ViewState<Bool> private var canLoadIntoCluster = false

    private var rows: [ImageRow] { search.isEmpty ? store.images : store.images.filter { $0.reference.localizedCaseInsensitiveContains(search) } }

    private var subtitle: String {
        guard store.engine.isRunning else { return "" }
        // A failed read keeps the previous list on screen; say so instead of hiding it.
        if store.imageError != nil && !store.images.isEmpty { return "\(store.images.count) local · not refreshed" }
        return "\(store.images.count) local" + (store.imageWarning != nil ? " · some could not be read" : "")
    }

    var body: some View {
        PageScaffold(title: "Images", subtitle: subtitle) {
            GlassControls {
                GlassSearchField(text: $search, prompt: "Repository or tag")
                Button { store.present(.build(BuildOptions())) } label: { HeaderIcon(systemName: "hammer") }
                    .buttonStyle(.plain).disabled(!store.engine.isRunning)
                    .help("Build an image from a Dockerfile (⇧⌘B)").accessibilityLabel("Build Image")
                HeaderMenu(systemName: "ellipsis", help: "Import, load and clean up images") {
                    Button("Import from Docker…") { store.present(.importImages) }
                    Button("Load Archive…") { store.loadImages() }
                    Divider()
                    Button("Remove Dangling Images…") { pendingPrune = false }
                    Button("Remove All Unused Images…") { pendingPrune = true }
                    Divider()
                    NativeActionsMenu(group: "Images")
                }
                .disabled(!store.engine.isRunning)
            }
            PrimaryActionButton(label: "Pull", title: "Pull Image (⇧⌘P)", systemImage: "arrow.down") { store.present(.pull) }
                .disabled(!store.engine.isRunning)
        } content: {
            content
        }
        .task(id: "\(store.engine.isRunning) \(store.installedVersion ?? "")") {
            guard store.engine.isRunning else { canLoadIntoCluster = false; return }
            canLoadIntoCluster = await store.help(for: ["k8s", "load-image"]) != nil
        }
        .confirmationDialog(pendingDelete.count == 1 ? "Delete “\(pendingDelete[0].reference)”?" : "Delete \(pendingDelete.count) images?",
                            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { pendingDelete.forEach { store.delete($0) } }
        } message: { Text("Containers that still use an image keep it from being deleted.") }
        .confirmationDialog(pendingPrune == true ? "Remove all unused images?" : "Remove dangling images?",
                            isPresented: Binding(get: { pendingPrune != nil }, set: { if !$0 { pendingPrune = nil } }), titleVisibility: .visible,
                            presenting: pendingPrune) { all in
            Button("Remove", role: .destructive) { store.pruneImages(all: all) }
        } message: { all in
            Text(all ? "Every image no container uses is deleted, including ones you pulled but have not run yet." : "Untagged images left behind by builds and pulls are deleted.")
        }
        .confirmationDialog("Push “\(pendingPush?.reference ?? "")”?", isPresented: Binding(get: { pendingPush != nil }, set: { if !$0 { pendingPush = nil } }),
                            titleVisibility: .visible, presenting: pendingPush) { image in
            Button("Push") { store.push(image) }
        } message: { image in Text("Uploads the image to \(image.repository.split(separator: "/").first.map(String.init) ?? "the registry"). Log in to the registry first if it needs credentials.") }
    }

    @ViewBuilder private var content: some View {
        if !store.engine.isRunning {
            EngineSetupView()
        } else if store.images.isEmpty {
            ContentUnavailableView {
                Label(store.imageError == nil ? "No Images" : "Could Not Read Images", systemImage: "square.3.layers.3d")
            } description: {
                Text(store.imageError ?? "Pull an image such as nginx:alpine or your project's base image.")
            } actions: {
                Button("Pull Image…") { store.present(.pull) }.buttonStyle(.borderedProminent)
            }
            .huggingGlassPanel(height: 320)
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: search).huggingGlassPanel(height: 300)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // 1.6.0 lists the images it can read; the CLI's message names the others.
                if let warning = store.imageWarning {
                    Label("Some images could not be read", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                        .help(warning).padding(.leading, 4)
                }
                imageList
            }
        }
    }

    private var imageList: some View {
        SelectableRows(items: rows, selection: $selection, rowHeight: ImageListRow.height,
                       onOpen: { image in store.present(.run(RunOptions(image: image.reference))) },
                       onDelete: { pendingDelete = $0 }) { image in
            ImageListRow(image: image)
        } menu: { chosen in
            if chosen.count == 1, let image = chosen.first {
                Button("Run Container…") { store.present(.run(RunOptions(image: image.reference))) }
                Divider()
                Button("Tag…") { store.present(.tag(image)) }
                Button("Push…") { pendingPush = image }
                if canLoadIntoCluster { Button("Load into Kubernetes Cluster…") { store.present(.loadIntoCluster(image)) } }
                Divider()
                Button("Inspect") { store.inspect(image) }
                Button("Copy Reference") { store.copy(image.reference) }
                Divider()
            }
            Button(chosen.count > 1 ? "Save \(chosen.count) Images…" : "Save as Archive…") { store.save(chosen) }.disabled(chosen.isEmpty)
            Divider()
            Button(chosen.count > 1 ? "Delete \(chosen.count) Images…" : "Delete…", role: .destructive) { pendingDelete = chosen }
                .disabled(chosen.isEmpty)
        }
        .huggingGlassPanel(height: 12 + CGFloat(rows.count) * ImageListRow.height)
        .onChange(of: store.images.map(\.id)) { _, ids in selection.formIntersection(ids) }
    }
}

private struct ImageListRow: View {
    static let height: CGFloat = 60
    @Environment(Store.self) private var store
    let image: ImageRow
    @Environment(\.rowSelected) private var selected
    @ViewState<Bool> private var hovering = false
    var body: some View {
        let busy = store.isBusy("image " + image.reference)
        let users = store.containers.filter { ImageReference.sameImage($0.image, image.reference) }
        HStack(spacing: 12) {
            RowIcon(systemName: "square.3.layers.3d", active: !users.isEmpty).symbolEffect(.pulse, isActive: busy)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(image.repository).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(image.tag).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.harborSub)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.harborSub.opacity(0.14), in: .capsule)
                }
                HStack(spacing: 8) {
                    Text(String(image.digest.prefix(19))).font(.system(size: 11).monospaced()).lineLimit(1)
                    if let created = image.created {
                        Text("Created \(created, format: .relative(presentation: .named))").help(created.formatted())
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Color.harborSub)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            if !users.isEmpty {
                Text(users.count == 1 ? "In use" : "Used by \(users.count)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.harborLive)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color.harbor.opacity(0.16), in: .capsule)
                    .help(users.map(\.name).joined(separator: ", "))
            }
            Text(image.size).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Color.harborSub)
            Group {
                if busy { ProgressView().controlSize(.small) }
                else {
                    Button("Run…") { store.present(.run(RunOptions(image: image.reference))) }
                        .buttonStyle(MiniButtonStyle()).opacity(hovering || selected ? 1 : 0)
                }
            }
            .frame(width: 58, alignment: .trailing)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct PullImageSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var reference = ""
    private var trimmed: String { reference.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Pull Image", systemImage: "arrow.down.circle").font(.title2.weight(.semibold))
            TextField("Image", text: $reference, prompt: Text("nginx:alpine or registry.example.com/team/app:tag"))
                .textFieldStyle(.roundedBorder).font(.body.monospaced()).onSubmit(pull)
            Text("The pull runs in the background; progress shows at the bottom of the window.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Pull", action: pull).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!ImageReference.isValid(trimmed))
            }
        }
        .padding(24).frame(width: 500)
    }
    private func pull() {
        guard ImageReference.isValid(trimmed) else { return }
        store.pull(trimmed); dismiss()
    }
}
