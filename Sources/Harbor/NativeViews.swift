import SwiftUI
import AppKit
import HarborCore

struct RuntimeView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(systemName: "cpu").font(.system(size: 42, weight: .light)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 6) { Text(store.connected ? "Native Engine Connected" : "Connect Apple Container").font(.title2.weight(.semibold)); Text("Harbor → container CLI → Apple Container").font(.callout).foregroundStyle(.secondary) }
                Spacer()
            }
            GroupBox("Runtime") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Image(systemName: FileManager.default.isExecutableFile(atPath: store.config.container) ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(.mint); Text("Apple Container CLI"); Spacer(); Text(store.config.container).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    Text(store.connectionMessage).font(.caption).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled)
                    HStack {
                        Button("Start Engine") { store.perform("Start Apple Container", command: store.config.nativeCommand(["system", "start", "--enable-kernel-install"]), timeout: 300) }.buttonStyle(.borderedProminent).disabled(store.busy || store.connected)
                        Button("Status") { store.perform("Engine Status", command: store.config.nativeCommand(["system", "status"])) }.disabled(store.busy)
                        Button("Version") { store.perform("Version Info", command: store.config.nativeCommand(["system", "version"])) }.disabled(store.busy)
                        SettingsLink { Text("Set Paths…") }
                    }
                    Text("The first start downloads the officially recommended kernel. Quitting Harbor does not stop the native engine or containers.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Install the Official Runtime") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Requires Apple Silicon and macOS 26+. Once the official container CLI is installed, every native action is available.").font(.callout)
                    HStack { Text("brew install container").font(.system(.body, design: .monospaced)).textSelection(.enabled); Spacer(); Button("Copy") { store.copy("brew install container") }; Link("Official Installer ↗", destination: URL(string: "https://github.com/apple/container/releases")!) }
                    Text("The native workflow needs no Docker, Socktainer or background compatibility proxy.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("System Tools") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    ForEach(NativeOperation.all.filter { $0.group == "System" }) { op in
                        Button { store.nativeOperation = op } label: { HStack { Image(systemName: op.destructive ? "exclamationmark.circle" : "gearshape"); Text(op.title); Spacer(); Image(systemName: "chevron.right").font(.caption2) }.padding(9) }.buttonStyle(.plain).disabled(store.busy)
                    }
                }.padding(8)
            }
            Text("Available features follow the local CLI --help. Linux machines and Kubernetes ship in newer versions; Kubernetes is an official experimental plugin. Advanced arguments are edited in the native command panel; interactive logins and admin operations are handed to Terminal.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct NativeSection: View {
    @EnvironmentObject var store: Store
    var group: String
    var list: [String]
    @ViewState<String> private var text = "Loading…"
    @ViewState<Bool> private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Label("From container \(list.joined(separator: " "))", systemImage: "terminal").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Refresh") { Task { await refresh() } }.disabled(loading || store.busy) }
            ScrollView(.horizontal) { Text(text.isEmpty ? "No resources." : text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(20).frame(minHeight: 120, alignment: .topLeading) }.frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            Text("Native Actions").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(NativeOperation.all.filter { $0.group == group }) { op in OperationCard(operation: op) }
            }
            if group == "Kubernetes" { Text("Creating a cluster pulls node images and merges ~/.kube/config. 1.5.0 has no k8s start; read the local help first. Harbor never creates clusters automatically.").font(.caption).foregroundStyle(.secondary) }
            if group == "Linux Machines" { Text("Machine creation controls the home directory mount. The example uses --home-mount none; choose read-only or read-write sharing as needed.").font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: group) { await refresh() }
        .onChange(of: store.busy) { _, busy in if !busy { Task { await refresh() } } }
    }
    private func refresh() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { text = try await Runner.checked(store.config.nativeCommand(list), timeout: 15) }
        catch { text = error.localizedDescription + "\n\nCheck the runtime; older CLIs may not support this feature." }
    }
}

struct OperationCard: View {
    @EnvironmentObject var store: Store
    var operation: NativeOperation
    var body: some View {
        Button { store.nativeOperation = operation } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(operation.title).font(.callout.weight(.medium)); Spacer(); Image(systemName: operation.terminal ? "arrow.up.right" : "chevron.right").font(.caption).foregroundStyle(.secondary) }
                Text("container " + operation.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        }.buttonStyle(.plain).disabled(store.busy)
    }
}

struct NativeCatalogView: View {
    @EnvironmentObject var store: Store
    @ViewState<String> private var search = ""
    @ViewState<String> private var raw = "--help"
    var groups: [String] { var seen = Set<String>(); return NativeOperation.all.map(\.group).filter { seen.insert($0).inserted } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Common actions have forms; everything else keeps a native argument entry. Choosing an action reads the local --help, so features are not pinned to one version.").font(.callout).foregroundStyle(.secondary)
            GroupBox("Custom Native Command") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("container").font(.system(.body, design: .monospaced)); TextField("Enter a subcommand and arguments", text: $raw).textFieldStyle(.roundedBorder) }
                    HStack {
                        Button("Open Command Panel") { store.nativeOperation = NativeOperation("Custom", "Custom Native Command", "", raw) }.disabled(store.busy)
                        Spacer(); Text("Arguments are only split; no pipes, redirects or shell expansion.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(10)
            }
            TextField("Search commands, actions or categories…", text: $search).textFieldStyle(.roundedBorder)
            ForEach(groups, id: \.self) { group in
                let ops = NativeOperation.all.filter { $0.group == group && (search.isEmpty || ($0.title + $0.id + $0.group).localizedCaseInsensitiveContains(search)) }
                if !ops.isEmpty { Text(group).font(.headline).padding(.top, 8); LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(ops) { OperationCard(operation: $0) } } }
            }
        }
    }
}

struct NativeOperationSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let initial: NativeOperation
    @ViewState<String> private var arguments = ""
    @ViewState<String> private var directory = ""
    @ViewState<String> private var help = "Reading local command help…"
    @ViewState<Bool> private var available = false
    @ViewState<Bool> private var terminal = false
    @ViewState<Bool> private var confirm = false
    @ViewState<String?> private var validation: String?
    private var admin: Bool { initial.path.starts(with: ["system", "dns"]) && initial.path.last != "list" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text(initial.title).font(.title2.weight(.semibold)); Text("container " + initial.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }; Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Arguments").font(.headline)
            TextEditor(text: $arguments).font(.system(.body, design: .monospaced)).frame(height: 74).padding(5).overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
            HStack { TextField("Working directory (optional; use an absolute path)", text: $directory).textFieldStyle(.roundedBorder); Button("Choose…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK { directory = panel.url?.path ?? "" } } }
            Toggle("Run in Terminal (interactive input / streaming logs)", isOn: $terminal).disabled(initial.terminal)
            if admin { Text("This native DNS operation needs administrator rights and will ask for authorization with sudo in Terminal.").font(.caption).foregroundStyle(.secondary) }
            if initial.path == ["k8s", "create"] || initial.path == ["k8s", "write-config"] { Text("This updates kubeconfig as the official CLI does; confirm the cluster name in the arguments.").font(.caption).foregroundStyle(.secondary) }
            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
            HStack { Text("Local Help").font(.headline); Spacer(); Button("Reload") { Task { await loadHelp() } } }
            ScrollView([.horizontal, .vertical]) { Text(help).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading) }.background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Copy Command") { do { store.copy(try makeCommand().display) } catch { validation = error.localizedDescription } }
                Spacer()
                Text(initial.destructive ? "This stops services or deletes resources." : "Calls the official CLI directly; arguments are not shell-expanded.").font(.caption).foregroundStyle(.secondary)
                Button(terminal ? "Run in Terminal ↗" : "Run") {
                    do { _ = try makeCommand(); if initial.destructive { confirm = true } else { execute() } } catch { validation = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(!available || store.busy)
            }
        }.padding(26).frame(width: 800, height: 670)
        .task { arguments = initial.example; terminal = initial.terminal; await loadHelp() }
        .confirmationDialog("Run \(initial.id)? Check the resource names in the arguments.", isPresented: $confirm, titleVisibility: .visible) { Button("Run", role: .destructive) { execute() } }
    }
    private func makeCommand() throws -> Command {
        var command = store.config.nativeCommand(initial.path + (try ArgumentTokenizer.split(arguments)))
        guard !command.arguments.isEmpty else { throw HarborError.message("Enter a subcommand or --help.") }
        if !directory.isEmpty {
            guard directory.hasPrefix("/"), FileManager.default.fileExists(atPath: directory) else { throw HarborError.message("The working directory does not exist or is not an absolute path.") }
            command.directory = directory
        }
        return command
    }
    private func loadHelp() async {
        available = false
        do {
            help = try await Runner.checked(store.config.nativeCommand(initial.path + ["--help"]), timeout: 10)
            guard NativeHelp.matches(help, path: initial.path) else {
                help = "The CLI did not return help for this subcommand. Check the version, engine status or plugins.\n\n" + help
                return
            }
            available = true
        }
        catch { help = error.localizedDescription + "\n\nCould not read help for this command. Check the CLI path, version and plugins." }
    }
    private func execute() {
        do {
            let command = try makeCommand(), useTerminal = terminal, useAdmin = admin
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                if useTerminal { store.openNativeTerminal(command.arguments, directory: command.directory, admin: useAdmin) }
                else { store.perform(initial.title, command: command, timeout: 1800) }
            }
        } catch { validation = error.localizedDescription }
    }
}
