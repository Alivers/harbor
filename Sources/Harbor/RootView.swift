import SwiftUI
import AppKit
import HarborCore

/// Sidebar destinations. `group` ties a page to its `NativeOperation` catalog group (matched by string).
enum Page: String, CaseIterable, Identifiable {
    case containers, images, compose, networks, volumes, build, machines, kubernetes, engine, registries, commands
    var id: String { rawValue }
    var title: String { switch self {
    case .containers: "Containers"; case .images: "Images"; case .compose: "Compose"
    case .networks: "Networks"; case .volumes: "Volumes"; case .build: "Builder"
    case .machines: "Linux Machines"; case .kubernetes: "Kubernetes"
    case .engine: "Engine"; case .registries: "Registries"; case .commands: "All Commands"
    } }
    var icon: String { switch self {
    case .containers: "shippingbox"; case .images: "square.3.layers.3d"; case .compose: "square.stack.3d.up"
    case .networks: "network"; case .volumes: "externaldrive"; case .build: "hammer"
    case .machines: "desktopcomputer"; case .kubernetes: "hexagon"
    case .engine: "cpu"; case .registries: "server.rack"; case .commands: "terminal"
    } }
    var group: String? { switch self {
    case .containers: "Containers"; case .images: "Images"; case .build: "Build"; case .networks: "Networks"
    case .volumes: "Volumes"; case .machines: "Linux Machines"; case .kubernetes: "Kubernetes"; case .registries: "Registries"
    case .compose, .engine, .commands: nil
    } }
}

struct SidebarSection: Identifiable {
    let title: String
    let pages: [Page]
    var id: String { title }
    static let all = [
        SidebarSection(title: "Workloads", pages: [.containers, .images, .compose]),
        SidebarSection(title: "Resources", pages: [.networks, .volumes, .build]),
        SidebarSection(title: "Environments", pages: [.machines, .kubernetes]),
        SidebarSection(title: "System", pages: [.engine, .registries, .commands])]
}

struct RootView: View {
    @Environment(Store.self) private var store
    @SceneStorage("page") private var page: Page = .containers
    /// Held explicitly so the sidebar stays put while the inspector opens; only the sidebar button hides it.
    @ViewState<NavigationSplitViewVisibility> private var columns: NavigationSplitViewVisibility = .all
    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(selection: $page)
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
        } detail: {
            detail
                .toolbar { ToolbarItem(placement: .automatic) { ActivityButton() } }
                // Floating controls belong to the glass layer above the content.
                .overlay(alignment: .bottom) { ActivityCapsule().padding(.bottom, 18) }
        }
        .sheet(item: $store.sheet) { route in SheetView(route: route) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refresh() }
        }
        .onChange(of: store.requestedPage) { _, requested in
            if let requested { page = requested; store.requestedPage = nil }
        }
        // Compose files, image archives and build contexts can be dropped anywhere in the window.
        .dropDestination(for: URL.self) { urls, _ in store.open(urls) }
    }
    @ViewBuilder private var detail: some View {
        switch page {
        case .containers: ContainersView()
        case .images: ImagesView()
        case .compose: ComposeView()
        case .engine: EngineView()
        case .commands: CatalogView()
        case .networks, .volumes, .build, .machines, .kubernetes, .registries: ResourceView(page: page).id(page)
        }
    }
}

private struct SheetView: View {
    let route: SheetRoute
    var body: some View {
        switch route {
        case .run(let options): RunContainerSheet(options: options)
        case .pull: PullImageSheet()
        case .operation(let request): NativeOperationSheet(request: request)
        case .output(let job): JobOutputSheet(job: job)
        case .build(let options): BuildImageSheet(options: options)
        case .tag(let image): TagImageSheet(image: image)
        case .createNetwork: CreateNetworkSheet()
        case .createVolume: CreateVolumeSheet()
        case .importImages: ImportImagesSheet()
        }
    }
}

private struct Sidebar: View {
    @Environment(Store.self) private var store
    @Binding var selection: Page
    var body: some View {
        List(selection: Binding(get: { Optional(selection) }, set: { if let page = $0 { selection = page } })) {
            ForEach(SidebarSection.all) { section in
                Section(section.title) {
                    ForEach(section.pages) { page in
                        Label(page.title, systemImage: page.icon).badge(badge(for: page)).tag(page)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { EngineFooter(selection: $selection) }
    }
    private func badge(for page: Page) -> Int {
        switch page {
        case .containers: store.containers.filter(\.running).count
        case .images: store.images.count
        default: 0
        }
    }
}

/// Engine state at the foot of the sidebar; a click opens the Engine page.
private struct EngineFooter: View {
    @Environment(Store.self) private var store
    @Binding var selection: Page
    var body: some View {
        Button { selection = .engine } label: {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.6), radius: store.engine.isRunning ? 3 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.medium)).contentTransition(.opacity)
                    Text("Apple Container").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8).padding(.bottom, 8)
        .animation(.smooth, value: store.engine)
    }
    private var title: String { switch store.engine {
    case .checking: "Connecting…"; case .missingCLI: "Not installed"; case .stopped: "Engine stopped"; case .running: "Engine running"
    } }
    private var color: Color { switch store.engine {
    case .running: .harborLive; case .checking: .secondary; case .missingCLI, .stopped: .orange
    } }
}
