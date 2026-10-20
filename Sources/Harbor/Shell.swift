import SwiftUI
import AppKit

// The window chrome of the design: no title bar, the traffic lights inside the sidebar pane, page titles floating on
// the frosted window, and small controls on clear Liquid Glass.

/// The window's close, minimize and zoom buttons, placed in the sidebar pane as in the design. They are the system's
/// own buttons (made with `NSWindow.standardWindowButton(_:for:)`), so they keep their look, states and zoom menu;
/// the title bar's copies are hidden.
struct WindowControls: NSViewRepresentable {
    func makeNSView(context: Context) -> ControlsView { ControlsView() }
    func updateNSView(_ view: ControlsView, context: Context) {}

    final class ControlsView: NSView {
        private var buttons: [NSButton] = []
        private var observers: [NSObjectProtocol] = []
        private var hovering = false
        override var intrinsicContentSize: NSSize { NSSize(width: 54, height: 16) }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            buttons.forEach { $0.removeFromSuperview() }
            buttons = []
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (index, type) in types.enumerated() {
                guard let button = NSWindow.standardWindowButton(type, for: window.styleMask) else { continue }
                button.setFrameOrigin(NSPoint(x: CGFloat(index) * 20, y: 0))
                addSubview(button)
                buttons.append(button)
            }
            hideTitleBarButtons()
            let center = NotificationCenter.default
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.redraw() }
                })
            }
            // The title bar can bring its own buttons back when the window leaves full screen.
            observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideTitleBarButtons() }
            })
        }
        private func hideTitleBarButtons() {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window?.standardWindowButton(type)?.isHidden = true }
        }
        /// AppKit asks the buttons' superview whether the pointer is over the group, to show the symbols on all three.
        @objc func _mouseInGroup(_ button: NSButton) -> Bool { hovering }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { hovering = true; redraw() }
        override func mouseExited(with event: NSEvent) { hovering = false; redraw() }
        private func redraw() { buttons.forEach { $0.needsDisplay = true } }
    }
}

/// Empty space that moves the window, which has no title bar; a double-click zooms or minimizes it as the
/// system setting for title bars says.
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
            .onTapGesture(count: 2) {
                guard let window = NSApp.keyWindow else { return }
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            }
    }
}

/// A page as the design lays it out: title and controls sit on the frosted window, the page's panes sit below,
/// and the activity capsule floats over the bottom of the column.
struct PageScaffold<Controls: View, Content: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var controls: Controls
    @ViewBuilder var content: Content
    @Environment(Store.self) private var store
    var body: some View {
        // While the capsule shows, the panes end above it, so it never covers a list's last rows.
        let capsule = !store.runningJobs.isEmpty || store.banner != nil
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 20, weight: .bold)).kerning(-0.2)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.harborSub).contentTransition(.numericText())
                    }
                }
                .lineLimit(1)
                .padding(.leading, 2)
                Spacer(minLength: 12)
                controls
            }
            .frame(height: 40)
            .background { WindowDragArea() }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.bottom, capsule ? 64 : 0)
        }
        .overlay(alignment: .bottom) { ActivityCapsule().padding(.bottom, 16) }
        .animation(.smooth(duration: 0.3), value: capsule)
    }
}

/// Small icon controls sharing one capsule of clear Liquid Glass, like the design's toolbar group.
struct GlassControls<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 4)
            .frame(height: 36)
            .glassEffect(.clear.interactive(), in: .capsule)
    }
}

/// An icon for `GlassControls`, as a button or menu label.
struct HeaderIcon: View {
    let systemName: String
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 32, height: 32)
            .contentShape(.circle)
            .opacity(enabled ? 1 : 0.4)
    }
}

/// A menu in `GlassControls`.
struct HeaderMenu<Content: View>: View {
    let systemName: String
    let help: String
    @ViewBuilder var content: Content
    var body: some View {
        Menu { content } label: { HeaderIcon(systemName: systemName) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help(help)
            .accessibilityLabel(help)
    }
}

/// The design's violet round button for a page's main action.
struct PrimaryActionButton: View {
    let title: String
    var systemImage = "plus"
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.harbor, in: .circle)
                // inset 0 1px 0 white .45, 0 6px 16px violet .4
                .overlay { Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .center)) }
                .shadow(color: Color.harbor.opacity(enabled ? 0.4 : 0), radius: 8, y: 6)
                .contentShape(.circle)
        }
        .buttonStyle(PressableStyle())
        .opacity(enabled ? 1 : 0.45)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Shrinks a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

/// The design's small glass buttons, such as Stop and Open Shell at the foot of the inspector.
struct MiniButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(configuration.role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.white.opacity(dark ? 0.08 : 0.45), in: .capsule)
            .overlay { Capsule().strokeBorder(Color.white.opacity(dark ? 0.12 : 0.7)) }
            .contentShape(.capsule)
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

/// A page's search: a magnifier on the glass that opens into a field. Escape clears and closes it.
struct GlassSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool
    @ViewState<Bool> private var open = false
    var body: some View {
        HStack(spacing: 2) {
            Button { open = true; focused = true } label: { HeaderIcon(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Search").accessibilityLabel("Search")
            if open || !text.isEmpty {
                TextField(prompt, text: $text, prompt: Text(prompt))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .frame(width: 150)
                    .onExitCommand { text = ""; focused = false; open = false }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                Button { text = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.harborSub) }
                    .buttonStyle(.plain).opacity(text.isEmpty ? 0 : 1).disabled(text.isEmpty)
                    .padding(.trailing, 6).help("Clear").accessibilityLabel("Clear search")
            }
        }
        .onChange(of: focused) { _, isFocused in if !isFocused && text.isEmpty { open = false } }
        .animation(.smooth(duration: 0.25), value: open)
    }
}

/// Segments drawn as pills, as in the design: the chosen one on a violet wash.
struct PillPicker<Option: Hashable & Identifiable & RawRepresentable>: View where Option.RawValue == String {
    @Binding var selection: Option
    let options: [Option]
    var small = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Scrolls sideways rather than clipping when the pills do not fit (narrow panes, larger text).
        ViewThatFits(in: .horizontal) {
            pills
            ScrollView(.horizontal) { pills }.scrollIndicators(.never)
        }
    }
    private var pills: some View {
        HStack(spacing: small ? 4 : 6) {
            ForEach(options) { option in
                let on = option == selection
                Button { selection = option } label: {
                    Text(option.rawValue)
                        .font(.system(size: small ? 11 : 12, weight: .semibold))
                        .foregroundStyle(on ? Color.primary : Color.harborSub)
                        .padding(.horizontal, small ? 8 : 11).padding(.vertical, small ? 4 : 5)
                        .background(on ? Color.harbor.opacity(scheme == .dark ? 0.24 : 0.2) : Color.clear, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.smooth(duration: 0.2), value: selection)
    }
}

/// A hairline between a pane's header and its rows.
struct PaneDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle().fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.45)).frame(height: 1).padding(.horizontal, 14)
    }
}

private struct RowSelectedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Set on a `SelectableRows` row while it is selected, so its actions show without hovering.
    var rowSelected: Bool {
        get { self[RowSelectedKey.self] }
        set { self[RowSelectedKey.self] = newValue }
    }
}

/// Rows on a pane with the design's violet selection, which stays violet when the list is not focused.
/// Click selects, Command-click toggles, Shift-click extends; arrow keys move, Return or a double-click opens,
/// Delete asks to delete, and the context menu acts on the selection when the clicked row is part of it.
struct SelectableRows<Item: Identifiable, Row: View, MenuContent: View>: View where Item.ID == String {
    let items: [Item]
    @Binding var selection: Set<String>
    var rowHeight: CGFloat = 60
    var onOpen: (Item) -> Void = { _ in }
    var onDelete: (([Item]) -> Void)?
    @ViewBuilder var row: (Item) -> Row
    @ViewBuilder var menu: ([Item]) -> MenuContent
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    @ViewState<String?> private var anchor: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                            .environment(\.rowSelected, selection.contains(item.id))
                            .padding(.horizontal, 10)
                            .frame(height: rowHeight)
                            .background(selection.contains(item.id) ? Color.harbor.opacity(scheme == .dark ? 0.16 : 0.14) : Color.clear,
                                        in: .rect(cornerRadius: 12, style: .continuous))
                            .contentShape(.rect)
                            .gesture(TapGesture().onEnded { click(item) })
                            .simultaneousGesture(TapGesture(count: 2).onEnded { selection = [item.id]; onOpen(item) })
                            .contextMenu { menu(targets(for: item)) }
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onMoveCommand { direction in move(direction, proxy: proxy) }
            .onKeyPress(.return) {
                guard let item = items.first(where: { selection.contains($0.id) }) else { return .ignored }
                onOpen(item); return .handled
            }
            .onDeleteCommand {
                let chosen = items.filter { selection.contains($0.id) }
                if !chosen.isEmpty { onDelete?(chosen) }
            }
            .animation(.smooth, value: items.map(\.id))
        }
    }
    private func targets(for item: Item) -> [Item] {
        selection.contains(item.id) ? items.filter { selection.contains($0.id) } : [item]
    }
    private func click(_ item: Item) {
        focused = true
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            anchor = item.id
        } else if modifiers.contains(.shift), let anchor, let from = items.firstIndex(where: { $0.id == anchor }),
                  let to = items.firstIndex(where: { $0.id == item.id }) {
            selection = Set(items[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [item.id]
            anchor = item.id
        }
    }
    private func move(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        guard !items.isEmpty, direction == .up || direction == .down else { return }
        let current = items.lastIndex { selection.contains($0.id) }
        let next: Int
        if let current { next = direction == .up ? max(current - 1, 0) : min(current + 1, items.count - 1) }
        else { next = direction == .up ? items.count - 1 : 0 }
        let id = items[next].id
        selection = [id]; anchor = id
        proxy.scrollTo(id)
    }
}

/// A titled group of label and value rows in a lighter well, for the inspector.
struct InfoSection<Content: View, Accessory: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    accessory
                }
                .padding(.horizontal, 2)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .card(padding: 10)
        }
    }
}

extension InfoSection where Accessory == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, accessory: { EmptyView() })
    }
}

/// One label and value in an `InfoSection`.
struct InfoRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value
    init(_ label: String, @ViewBuilder value: () -> Value) { self.label = label; self.value = value() }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color.harborSub).lineLimit(1)
            Spacer(minLength: 8)
            value.font(.system(size: 12)).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4).padding(.horizontal, 2)
    }
}

extension InfoRow where Value == Text {
    init(_ label: String, text: String) { self.init(label) { Text(text) } }
}

extension View {
    /// A vertically scrolling page of panes. The scroll view reaches 10 pt past the column on each side, into the
    /// gaps, so the panes' shadows are not cut off at their edges.
    func paneScroll() -> some View {
        ScrollView { self.padding(.horizontal, 10).padding(.bottom, 64) }
            .padding(.horizontal, -10)
    }
}
