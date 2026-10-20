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

/// The window as the design draws it: no title bar, and panes of glass floating over the wallpaper with gaps
/// between them. The sidebar is a pane of its own, with the window's buttons inside it.
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(BackdropCache.self) private var backdrop
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(Preference.backdropTint) private var tint = Preference.defaultBackdropTint
    @SceneStorage("page") private var page: Page = .containers
    var body: some View {
        @Bindable var store = store
        HStack(spacing: 14) {
            SidebarPane(selection: $page).frame(width: 208)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .foregroundStyle(Color.harborInk)
        // The gaps between the panes move the window.
        .background { WindowDragArea() }
        .background(alignment: .topLeading) {
            Wallpaper(dark: scheme == .dark).opacity(reduceTransparency ? 1 : tint)
        }
        .clipped()
        .coordinateSpace(.named(Backdrop.space))
        .ignoresSafeArea()
        .onAppear { backdrop.prepare(dark: scheme == .dark) }
        .onChange(of: scheme) { _, scheme in backdrop.prepare(dark: scheme == .dark) }
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

/// The sidebar pane of the design: the window's buttons, sections of pages with a violet selection, and the engine.
private struct SidebarPane: View {
    @Environment(Store.self) private var store
    @Binding var selection: Page
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WindowControls().frame(width: 54, height: 16).padding(.leading, 6)
                Spacer()
            }
            .frame(height: 16)
            .background { WindowDragArea() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SidebarSection.all) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.harborSub)
                                .padding(.horizontal, 9).padding(.bottom, 4)
                            ForEach(section.pages) { page in
                                SidebarRow(page: page, selected: selection == page, badge: badge(for: page)) { selection = page }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            EngineFooter(selection: $selection)
        }
        .padding(EdgeInsets(top: 16, leading: 10, bottom: 12, trailing: 10))
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel()
    }
    private func badge(for page: Page) -> Int {
        switch page {
        case .containers: store.containers.filter(\.running).count
        case .images: store.images.count
        default: 0
        }
    }
}

private struct SidebarRow: View {
    let page: Page
    let selected: Bool
    let badge: Int
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @ViewState<Bool> private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: page.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.harbor : Color.harborSub)
                    .frame(width: 18)
                Text(page.title).font(.system(size: 13, weight: selected ? .semibold : .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Color.harborSub)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(fill, in: .rect(cornerRadius: 9, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
    private var fill: Color {
        if selected { return Color.harbor.opacity(scheme == .dark ? 0.22 : 0.2) }
        return hovering ? Color.harbor.opacity(0.07) : .clear
    }
}

/// Engine state at the foot of the sidebar (a click opens the Engine page), next to the recent activity.
private struct EngineFooter: View {
    @Environment(Store.self) private var store
    @Binding var selection: Page
    var body: some View {
        HStack(spacing: 4) {
            Button { selection = .engine } label: {
                HStack(spacing: 10) {
                    Circle().fill(color).frame(width: 9, height: 9)
                        .shadow(color: color.opacity(store.engine.isRunning ? 0.8 : 0), radius: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 12, weight: .semibold)).contentTransition(.opacity)
                        Text("Apple Container").font(.system(size: 11)).foregroundStyle(Color.harborSub)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            ActivityButton()
        }
        .animation(.smooth, value: store.engine)
    }
    private var title: String { switch store.engine {
    case .checking: "Connecting…"; case .missingCLI: "Not installed"; case .stopped: "Engine stopped"; case .running: "Engine running"
    } }
    private var color: Color { switch store.engine {
    case .running: .harbor; case .checking: .secondary; case .missingCLI, .stopped: .orange
    } }
}
