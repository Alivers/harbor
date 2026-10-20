import SwiftUI
import HarborCore

struct ImagesView: View {
    @Environment(Store.self) private var store
    @ViewState<String> private var search = ""
    @ViewState<Set<String>> private var selection: Set<String> = []
    @ViewState<[ImageRow]> private var pendingDelete: [ImageRow] = []
    @ViewState<Bool?> private var pendingPrune: Bool?
    @ViewState<ImageRow?> private var pendingPush: ImageRow?

    private var rows: [ImageRow] { search.isEmpty ? store.images : store.images.filter { $0.reference.localizedCaseInsensitiveContains(search) } }

    var body: some View {
        content
            .navigationTitle("Images")
            .navigationSubtitle(store.engine.isRunning ? "\(store.images.count) local" : "")
            .searchable(text: $search, placement: .toolbar, prompt: "Repository or tag")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.present(.pull) } label: { Label("Pull Image", systemImage: "arrow.down.circle") }
                        .disabled(!store.engine.isRunning).help("Pull an image (⇧⌘P)")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { store.present(.build(BuildOptions())) } label: { Label("Build Image", systemImage: "hammer") }
                        .disabled(!store.engine.isRunning).help("Build an image from a Dockerfile (⇧⌘B)")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Import from Docker…") { store.present(.importImages) }
                        Button("Load Archive…") { store.loadImages() }
                        Divider()
                        Button("Remove Dangling Images…") { pendingPrune = false }
                        Button("Remove All Unused Images…") { pendingPrune = true }
                        Divider()
                        NativeActionsMenu(group: "Images")
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                    .disabled(!store.engine.isRunning)
                    .help("Import, load and clean up images")
                }
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
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            List(selection: $selection) {
                ForEach(rows) { ImageListRow(image: $0) }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let chosen = store.images.filter { ids.contains($0.id) }
                if chosen.count == 1, let image = chosen.first {
                    Button("Run Container…") { store.present(.run(RunOptions(image: image.reference))) }
                    Divider()
                    Button("Tag…") { store.present(.tag(image)) }
                    Button("Push…") { pendingPush = image }
                    Button("Copy Reference") { store.copy(image.reference) }
                    Divider()
                }
                Button(chosen.count > 1 ? "Save \(chosen.count) Images…" : "Save as Archive…") { store.save(chosen) }.disabled(chosen.isEmpty)
                Divider()
                Button(chosen.count > 1 ? "Delete \(chosen.count) Images…" : "Delete…", role: .destructive) { pendingDelete = chosen }
                    .disabled(chosen.isEmpty)
            } primaryAction: { ids in
                if let image = store.images.first(where: { ids.contains($0.id) }) { store.present(.run(RunOptions(image: image.reference))) }
            }
            .animation(.smooth, value: rows)
            .glassList()
        }
    }
}

private struct ImageListRow: View {
    @Environment(Store.self) private var store
    let image: ImageRow
    @ViewState<Bool> private var hovering = false
    var body: some View {
        let busy = store.isBusy("image " + image.reference)
        HStack(spacing: 12) {
            RowIcon(systemName: "square.3.layers.3d").symbolEffect(.pulse, isActive: busy)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(image.repository).font(.body.weight(.medium)).lineLimit(1)
                    Text(image.tag).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: .capsule)
                }
                HStack(spacing: 8) {
                    Text(String(image.digest.prefix(19))).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                    if let created = image.created {
                        Text("Created \(created, format: .relative(presentation: .named))").font(.caption).foregroundStyle(.tertiary).help(created.formatted())
                    }
                }
            }
            Spacer(minLength: 12)
            let users = store.containers.filter { ImageReference.sameImage($0.image, image.reference) }
            if !users.isEmpty {
                Text(users.count == 1 ? "In use" : "Used by \(users.count)").font(.caption.weight(.medium)).foregroundStyle(Color.harborText)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.harbor.opacity(0.12), in: .capsule)
                    .help(users.map(\.name).joined(separator: ", "))
            }
            Text(image.size).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Group {
                if busy { ProgressView().controlSize(.small) }
                else {
                    Button("Run…") { store.present(.run(RunOptions(image: image.reference))) }
                        .controlSize(.small).opacity(hovering ? 1 : 0)
                }
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
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
