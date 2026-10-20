import SwiftUI
import AppKit
import HarborCore

// Explicit alias selects the property-wrapper type on SDKs that also export a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

@main struct HarborApp: App {
    @ViewState<Store> private var store = Store()
    @AppStorage(Preference.menuBarExtra) private var showMenuBarExtra = true
    var body: some Scene {
        // One window: the store's sheet and activity state belong to a single place.
        Window("Harbor", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 600)
                .tint(.harbor)
                // The window is lightly frosted glass: the desktop and the windows below show as color, never as
                // legible detail.
                .containerBackground(for: .window) { WindowBackdrop() }
        }
        // No title bar: the panes float right up to the top, and the window's buttons sit in the sidebar pane.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands { HarborCommands(store: store) }
        Settings { SettingsView().environment(store).tint(.harbor) }
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarContent().environment(store)
        } label: {
            Label("Harbor", systemImage: "shippingbox.fill")
        }
    }
}

struct HarborCommands: Commands {
    let store: Store
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Run Container…") { store.present(.run(RunOptions())) }.keyboardShortcut("n")
            Button("Pull Image…") { store.present(.pull) }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Build Image…") { store.present(.build(BuildOptions())) }.keyboardShortcut("b", modifiers: [.command, .shift])
            Divider()
            Button("Import Compose Project…") { store.importProject() }.keyboardShortcut("o")
            Button("Import Images from Docker…") { store.present(.importImages) }
            Button("Load Image Archive…") { store.loadImages() }
        }
        CommandGroup(after: .toolbar) {
            Button("Refresh") { Task { await store.refresh() } }.keyboardShortcut("r")
            Divider()
        }
        CommandMenu("Go") {
            ForEach(Array(SidebarSection.all.flatMap(\.pages).enumerated()), id: \.element) { index, page in
                if index < 9 {
                    Button(page.title) { store.requestedPage = page }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                } else {
                    Button(page.title) { store.requestedPage = page }
                }
            }
        }
    }
}
