import SwiftUI
import AppKit
import HarborCore

/// Read-only monospaced text for command output and logs. Backed by NSTextView so multi-megabyte
/// output stays fast: new text is appended instead of re-laid out, the view keeps following the end
/// while the reader is at the bottom, and Command-F opens the system find bar.
struct LogTextView: NSViewRepresentable {
    var text: String
    /// Identifies where the text comes from; a new source replaces the content instead of appending.
    var source: AnyHashable
    /// Follow the end of growing output (logs) rather than starting at the top (help, JSON).
    var followsEnd = true

    final class Coordinator { var source: AnyHashable?; var length = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isRichText = false
            textView.drawsBackground = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.textContainerInset = NSSize(width: 10, height: 12)
        }
        return scrollView
    }
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, let storage = textView.textStorage else { return }
        let coordinator = context.coordinator, length = text.utf16.count
        if coordinator.source != source || length < coordinator.length {
            storage.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
            if followsEnd { textView.scrollToEndOfDocument(nil) } else { textView.scrollToBeginningOfDocument(nil) }
        } else if length > coordinator.length {
            let atEnd = scrollView.contentView.bounds.maxY >= textView.bounds.maxY - 24
            storage.append(NSAttributedString(string: (text as NSString).substring(from: coordinator.length), attributes: Self.attributes))
            if followsEnd && atEnd { textView.scrollToEndOfDocument(nil) }
        }
        coordinator.source = source; coordinator.length = length
    }
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular), .foregroundColor: NSColor.labelColor]
}

/// A log or report panel: text in a lighter well, with a placeholder while empty.
struct OutputPanel: View {
    var text: String
    var source: AnyHashable
    var followsEnd = true
    var placeholder = "No output."
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        LogTextView(text: text, source: source, followsEnd: followsEnd)
            .overlay { if text.isEmpty { Text(placeholder).foregroundStyle(Color.harborSub) } }
            .background(scheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.55), in: shape)
            .overlay { shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.1 : 0.7)).allowsHitTesting(false) }
    }
}

/// Running or stopped, as the design's small pill: deep violet on a violet wash, or muted.
struct StateBadge: View {
    let state: String
    let running: Bool
    var body: some View {
        Text(state.capitalized)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(running ? Color.harborLive : Color.harborSub)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background((running ? Color.harbor.opacity(0.16) : Color.harborSub.opacity(0.14)), in: .capsule)
            .contentTransition(.interpolate)
    }
}

/// Published ports as links that open the service in the browser.
struct PortLinks: View {
    let mappings: [PortMapping]
    var limit = 2
    var running = true
    var body: some View {
        ForEach(mappings.prefix(limit), id: \.self) { port in
            if let url = port.url {
                Link(destination: url) {
                    Label(port.label, systemImage: "arrow.up.forward").labelStyle(.titleAndIcon)
                        .foregroundStyle(running ? Color.harborLive : Color.harborSub)
                }
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .help("Open \(url.absoluteString)")
            } else {
                Text(port.label).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Color.harborSub)
            }
        }
        if mappings.count > limit { Text("+\(mappings.count - limit)").font(.system(size: 11)).foregroundStyle(Color.harborSub) }
    }
}

/// The design's icon tile for list rows: violet on a violet wash when active, muted otherwise.
struct RowIcon: View {
    let systemName: String
    var active = true
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(active ? Color.harbor : Color.harborSub)
            .frame(width: 34, height: 34)
            .background((active ? Color.harbor.opacity(0.16) : Color.harborSub.opacity(0.14)), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

/// An editable list of single-line entries, such as port mappings, for grouped forms.
struct EntryListEditor: View {
    struct Entry: Identifiable, Hashable { var id = UUID(); var text = "" }
    @Binding var entries: [Entry]
    let placeholder: String
    let addTitle: String
    var body: some View {
        ForEach($entries) { $entry in
            HStack {
                TextField(addTitle, text: $entry.text, prompt: Text(placeholder)).labelsHidden().font(.body.monospaced())
                Button { withAnimation(.smooth) { entries.removeAll { $0.id == entry.id } } } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove")
            }
        }
        Button { withAnimation(.smooth) { entries.append(Entry()) } } label: { Label(addTitle, systemImage: "plus.circle") }
            .buttonStyle(.borderless)
    }
}
