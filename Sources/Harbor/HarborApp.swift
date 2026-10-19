import SwiftUI
import AppKit
import HarborCore

// Explicit alias selects the property-wrapper type on SDKs that also export a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Color {
    /// Harbor's accent: a calm sea green that stays legible on Liquid Glass in light and dark mode.
    static let harbor = Color(red: 0.20, green: 0.70, blue: 0.53)
}

@main struct HarborApp: App {
    @ViewState<Store> private var store = Store()
    @AppStorage(Preference.menuBarExtra) private var showMenuBarExtra = true
    var body: some Scene {
        // One window: the store's sheet and activity state belong to a single place.
        Window("Harbor", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 880, minHeight: 560)
                .tint(.harbor)
        }
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
    }
}
