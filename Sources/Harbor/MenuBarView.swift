import SwiftUI
import AppKit
import HarborCore

/// The menu bar extra: engine state and quick container actions, available while the window is closed.
struct MenuBarContent: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(engineTitle)
        if store.engine.isRunning {
            Button("Stop Engine") { store.stopEngine() }.disabled(store.isBusy("engine"))
        } else if store.engine.isInstalled {
            Button("Start Engine") { store.startEngine() }.disabled(store.isBusy("engine"))
        }
        if store.engine.isRunning {
            Divider()
            let running = store.containers.filter(\.running)
            let stopped = store.containers.filter { !$0.running }
            if running.isEmpty { Text("No running containers") }
            ForEach(running) { c in
                Menu(c.name) {
                    ForEach(c.portMappings.compactMap(\.url), id: \.self) { url in
                        Button("Open \(url.host() ?? "localhost"):\(url.port ?? 0)") { NSWorkspace.shared.open(url) }
                    }
                    Button("Open Shell in Terminal") { store.openShell(c) }
                    Divider()
                    Button("Restart") { store.restart(c) }.disabled(store.isBusy(c.id))
                    Button("Stop") { store.stop(c) }.disabled(store.isBusy(c.id))
                }
            }
            if !stopped.isEmpty {
                Menu("Stopped (\(stopped.count))") {
                    ForEach(stopped) { c in Button("Start \(c.name)") { store.start(c) }.disabled(store.isBusy(c.id)) }
                }
            }
            Divider()
            Button("Run Container…") { show(); store.present(.run(RunOptions())) }
        }
        Divider()
        Button("Open Harbor") { show() }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Harbor") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
    private var engineTitle: String {
        switch store.engine {
        case .checking: "Apple Container: connecting…"
        case .missingCLI: "Apple Container: not installed"
        case .stopped: "Apple Container: stopped"
        case .running: "Apple Container: running · \(store.containers.filter(\.running).count) running"
        }
    }
    private func show() {
        openWindow(id: "main")
        NSApplication.shared.activate()
    }
}
