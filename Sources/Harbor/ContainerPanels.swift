import SwiftUI
import AppKit
import Charts
import HarborCore

/// Live CPU and memory for one running container. `container stats` reports cumulative counters, so each
/// point compares a sample with the one before it; samples are kept only while this view is open.
struct ContainerStatsView: View {
    @Environment(Store.self) private var store
    let container: ContainerRow
    struct Sample: Identifiable {
        let time: Date
        let cpu: Double
        let memory: Double
        var id: Date { time }
    }
    @ViewState<[Sample]> private var samples: [Sample] = []
    @ViewState<ContainerStats?> private var latest: ContainerStats?
    @ViewState<(rx: Double?, tx: Double?)> private var network: (rx: Double?, tx: Double?) = (nil, nil)
    @ViewState<String?> private var failure: String?
    var body: some View {
        Group {
            if !container.running {
                ContentUnavailableView("Not Running", systemImage: "chart.xyaxis.line", description: Text("Start the container to see its CPU and memory."))
            } else if let failure {
                ContentUnavailableView { Label("No Statistics", systemImage: "exclamationmark.triangle") } description: { Text(failure).textSelection(.enabled) }
            } else if latest == nil {
                ProgressView("Sampling…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView { content.padding(12) }
            }
        }
        .task(id: container.id + (container.running ? " running" : "")) { await sample() }
    }
    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    metric("CPU", samples.last.map { String(format: "%.1f%%", $0.cpu) } ?? "—")
                    metric("Memory", memoryText)
                }
                GridRow {
                    metric("Network in", network.rx.map(rate) ?? "—")
                    metric("Network out", network.tx.map(rate) ?? "—")
                }
                GridRow {
                    metric("Disk read", latest?.blockReadBytes.map { bytes(Double($0)) } ?? "—")
                    metric("Processes", latest?.numProcesses.map { String($0) } ?? "—")
                }
            }
            .card()
            chart("CPU", unit: "%", floor: 100) { $0.cpu }
            chart("Memory", unit: "MB", floor: Double(latest?.memoryLimitBytes ?? 0) / 1_048_576) { $0.memory / 1_048_576 }
            Text("100% CPU is one fully busy core. Values update every few seconds while this tab is open.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var memoryText: String {
        guard let used = latest?.memoryUsageBytes else { return "—" }
        let limit = latest?.memoryLimitBytes.map { " of " + bytes(Double($0)) } ?? ""
        return bytes(Double(used)) + limit
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit().weight(.medium)).contentTransition(.numericText())
        }
    }
    /// The y axis starts at zero and reaches at least `floor` (100% CPU, the memory limit), so small changes stay small.
    private func chart(_ title: String, unit: String, floor: Double, value: @escaping (Sample) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Chart(samples) { sample in
                AreaMark(x: .value("Time", sample.time), y: .value(unit, value(sample)))
                    .foregroundStyle(LinearGradient(colors: [Color.harbor.opacity(0.35), Color.harbor.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", sample.time), y: .value(unit, value(sample)))
                    .foregroundStyle(Color.harbor).interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...max(floor, samples.map(value).max() ?? 0, 1))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
            .frame(height: 120)
            .animation(.smooth, value: samples.count)
        }
        .card()
    }
    private func rate(_ value: Double) -> String { bytes(value) + "/s" }
    private func bytes(_ value: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory) }

    /// Each `stats` call itself takes about two seconds; the loop ends when the view goes away.
    private func sample() async {
        samples = []; latest = nil; failure = nil; network = (nil, nil)
        guard container.running else { return }
        var previous: (ContainerStats, Date)?
        while !Task.isCancelled {
            do {
                let text = try await store.read(["stats", "--format", "json", "--no-stream", container.id], timeout: 20)
                guard let current = try NativeParser.stats(text).first(where: { $0.id == container.id }) else {
                    throw HarborError.message("The CLI returned no statistics for this container.")
                }
                let now = Date()
                if let previous {
                    let (earlier, then) = previous
                    let interval = now.timeIntervalSince(then)
                    let cpu = ContainerStats.cpuPercent(from: earlier, to: current, interval: interval) ?? 0
                    samples.append(Sample(time: now, cpu: cpu, memory: Double(current.memoryUsageBytes ?? 0)))
                    if samples.count > 60 { samples.removeFirst(samples.count - 60) }
                    network = (ContainerStats.rate(earlier.networkRxBytes, current.networkRxBytes, interval: interval),
                               ContainerStats.rate(earlier.networkTxBytes, current.networkTxBytes, interval: interval))
                }
                latest = current; previous = (current, now); failure = nil
            } catch {
                if Task.isCancelled { return }
                failure = error.localizedDescription; return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// A file browser for a running container: lists folders with the container's own `ls`,
/// downloads with `container copy`, and uploads files picked or dropped onto the list.
struct ContainerFilesView: View {
    @Environment(Store.self) private var store
    let container: ContainerRow
    @ViewState<String> private var path = "/"
    @ViewState<String> private var typedPath = "/"
    @ViewState<[ContainerFiles.Entry]> private var entries: [ContainerFiles.Entry] = []
    @ViewState<String?> private var failure: String?
    @ViewState<Bool> private var loading = false
    @ViewState<String?> private var selection: String?
    @ViewState<Bool> private var dropTargeted = false
    var body: some View {
        if !container.running {
            ContentUnavailableView("Not Running", systemImage: "folder", description: Text("Start the container to browse its files."))
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button { go(ContainerFiles.parent(of: path)) } label: { Image(systemName: "chevron.up") }
                        .disabled(path == "/").help("Enclosing folder").accessibilityLabel("Enclosing folder")
                    TextField("Path", text: $typedPath).textFieldStyle(.roundedBorder).font(.callout.monospaced())
                        .onSubmit { go(typedPath) }
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Reload").accessibilityLabel("Reload")
                    Button { upload() } label: { Image(systemName: "square.and.arrow.up") }.help("Upload files to this folder").accessibilityLabel("Upload")
                }
                .buttonStyle(.borderless)
                Group {
                    if let failure {
                        ContentUnavailableView { Label("Cannot List This Folder", systemImage: "exclamationmark.triangle") } description: {
                            Text(failure + "\n\nImages without ls (distroless, scratch) cannot be browsed; Download still works for a known path.").textSelection(.enabled)
                        } actions: {
                            if path != "/" { Button("Download “\(URL(fileURLWithPath: path).lastPathComponent)”") { store.download(path, from: container) } }
                        }
                    } else if loading && entries.isEmpty {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(entries, selection: $selection) { entry in
                            Label(entry.name, systemImage: entry.isDirectory ? "folder.fill" : "doc")
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .contextMenu(forSelectionType: String.self) { names in
                            if let name = names.first, let entry = entries.first(where: { $0.name == name }) {
                                if entry.isDirectory { Button("Open") { go(ContainerFiles.join(path, name)) } }
                                Button("Download…") { store.download(ContainerFiles.join(path, name), from: container) }
                                Button("Copy Path") { store.copy(ContainerFiles.join(path, name)) }
                            }
                        } primaryAction: { names in
                            guard let name = names.first, let entry = entries.first(where: { $0.name == name }) else { return }
                            if entry.isDirectory { go(ContainerFiles.join(path, name)) } else { store.download(ContainerFiles.join(path, name), from: container) }
                        }
                        .overlay { if entries.isEmpty && !loading { Text("Empty folder").foregroundStyle(.secondary) } }
                        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.harbor, lineWidth: 2) } }
                        .dropDestination(for: URL.self) { urls, _ in
                            store.upload(urls, to: path, in: container); return true
                        } isTargeted: { dropTargeted = $0 }
                    }
                }
                Text("Double-click a folder to open it, or a file to download it. Drop files here to upload them.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding([.horizontal, .bottom], 12)
            .task(id: "\(container.id) \(path) \(store.changeCount)") { await load() }
        }
    }
    private func go(_ target: String) {
        guard let normalized = ContainerFiles.normalize(target) else { typedPath = path; return }
        selection = nil; path = normalized; typedPath = normalized
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let output = try await store.read(ContainerFiles.listArguments(container: container.id, path: path), timeout: 15)
            entries = ContainerFiles.parse(output); failure = nil
        } catch {
            if !Task.isCancelled { entries = []; failure = error.localizedDescription }
        }
    }
    private func upload() {
        let panel = NSOpenPanel(); panel.title = "Upload to \(path)"
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        store.upload(panel.urls, to: path, in: container)
    }
}
