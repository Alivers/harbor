import SwiftUI
import HarborCore

/// The floating status capsule: what is running now, then how the last job ended. It lives on the
/// Liquid Glass layer above the content and morphs between those states instead of popping.
struct ActivityCapsule: View {
    @Environment(Store.self) private var store
    @Namespace private var glass
    @ViewState<Bool> private var showList = false
    var body: some View {
        let running = store.runningJobs
        GlassEffectContainer(spacing: 12) {
            if let job = running.first {
                Button { showList = true } label: {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(job.title).lineLimit(1)
                        if running.count > 1 {
                            Text("+\(running.count - 1)").foregroundStyle(.secondary).contentTransition(.numericText())
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("activity", in: glass)
                .help("Show activity")
            } else if let job = store.banner {
                HStack(spacing: 10) {
                    Button { store.present(.output(job)) } label: {
                        HStack(spacing: 8) {
                            JobStatusIcon(status: job.status)
                            Text(job.status == .failed ? "\(job.title) failed" : job.title).lineLimit(1)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Show output")
                    Button { store.banner = nil } label: { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Dismiss")
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .glassEffect(job.status == .failed ? .regular.tint(.red.opacity(0.25)).interactive() : .regular.interactive(), in: .capsule)
                .glassEffectID("activity", in: glass)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.smooth(duration: 0.35), value: running.map { $0.id })
        .animation(.smooth(duration: 0.35), value: store.banner?.id)
        .popover(isPresented: $showList, arrowEdge: .top) { ActivityList().frame(width: 380) }
    }
}

/// Toolbar entry to the recent jobs, with a pulse while something runs.
struct ActivityButton: View {
    @Environment(Store.self) private var store
    @ViewState<Bool> private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Label("Activity", systemImage: "clock.arrow.circlepath")
                .symbolEffect(.pulse, isActive: !store.runningJobs.isEmpty)
        }
        .help("Recent activity")
        .popover(isPresented: $showing, arrowEdge: .bottom) { ActivityList().frame(width: 380) }
    }
}

struct ActivityList: View {
    @Environment(Store.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                Button("Clear Finished") { store.clearFinishedJobs() }
                    .buttonStyle(.borderless).disabled(!store.jobs.contains { !$0.isRunning })
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if store.jobs.isEmpty {
                ContentUnavailableView("No Activity Yet", systemImage: "clock", description: Text("Actions you take appear here with their output."))
                    .frame(height: 200)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) { ForEach(store.jobs) { JobRow(job: $0) } }.padding(6)
                }
                .frame(maxHeight: 420)
            }
        }
    }
}

private struct JobRow: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let job: Job
    @ViewState<Bool> private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            JobStatusIcon(status: job.status).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).lineLimit(1)
                Text(job.started, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if job.isRunning { Button("Stop") { job.cancel() }.controlSize(.small) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { dismiss(); store.present(.output(job)) }
    }
}

struct JobStatusIcon: View {
    let status: Job.Status
    var body: some View {
        switch status {
        case .running: ProgressView().controlSize(.small)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.harbor)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .canceled: Image(systemName: "stop.circle").foregroundStyle(.secondary)
        }
    }
}

/// A job's output while it runs and after it ends.
struct JobOutputSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let job: Job
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                JobStatusIcon(status: job.status)
                Text(job.title).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer()
                if job.isRunning { Button("Stop") { job.cancel() } }
                Button { store.copy(job.output) } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            OutputPanel(text: job.output, source: job.id, placeholder: job.isRunning ? "Waiting for output…" : "No output.")
            Text(job.isRunning ? "Output streams in as the command writes it. Stopping does not undo work the engine already started."
                               : "Output can include environment variables or tokens; review it before sharing.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 840, minHeight: 440, idealHeight: 560)
    }
}
