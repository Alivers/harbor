import SwiftUI
import AppKit

// Aurora Ice: an icy backdrop with violet for the brand and mint for things that are running.
// Every color has a light and a dark value; dark mode is a deep-indigo take on the same hues, not an inversion.

extension Color {
    /// Violet: tint, selection and brand icons. Dark enough behind white text in both modes.
    static let harbor = Color(light: 0x5F4FF5, dark: 0x6656F0)
    /// Violet for small text on glass, where the fill color would be too dark in dark mode.
    static let harborText = Color(light: 0x5F4FF5, dark: 0xA99EFF)
    /// Mint: running containers, a connected service, success.
    static let harborLive = Color(light: 0x08785D, dark: 0x5EE6B5)

    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// How content panels are drawn. Floating controls always use the system's clear Liquid Glass.
enum GlassStyle: String, CaseIterable, Identifiable {
    /// Frosted, with a bright edge, an inner glow and a top sheen: glass with some thickness.
    case crystal = "Crystal"
    /// The system's clear Liquid Glass: barely blurred, so the backdrop stays visible.
    case clear = "Clear"
    var id: String { rawValue }
}

/// The window's background: the desktop, blurred through the window, under an aurora tint.
/// It covers the whole window, sidebar and toolbar included, so the glass everywhere has something to show.
struct WindowBackdrop: View {
    @AppStorage(Preference.backdropTint) private var tint = Preference.defaultBackdropTint
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) } else { DesktopBlur() }
            AuroraBackdrop().opacity(reduceTransparency ? 0.5 : tint)
        }
        .ignoresSafeArea()
    }
}

/// What lies behind the window, blurred by the window server.
private struct DesktopBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The aurora itself. On its own it is opaque; `WindowBackdrop` lays it over the desktop as a tint.
struct AuroraBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.62, 0.42], [1, 0.5],
            [0, 1], [0.45, 1], [1, 1]
        ], colors: (scheme == .dark ? Self.dark : Self.light).map(Color.init(hex:)))
    }
    // Ice, lilac and mint by day; indigo, violet and deep teal by night. Saturated enough to read as color once it is a tint.
    private static let light: [UInt32] = [0xDCE4FF, 0xC2B4FF, 0xB3D8FF, 0xEAE6FF, 0xD3DBFF, 0xA9EDD6, 0xFFD0E2, 0xDDE6FF, 0xCBC0FF]
    private static let dark: [UInt32] = [0x0E1030, 0x2E2378, 0x0E2A52, 0x121433, 0x191C46, 0x0D4A45, 0x35195A, 0x101333, 0x271F6E]
}

/// A content panel in the chosen `GlassStyle`; solid when Reduce Transparency is on.
struct GlassPanel: ViewModifier {
    var radius: CGFloat
    @AppStorage(Preference.glassStyle) private var style = GlassStyle.crystal.rawValue
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.12)).allowsHitTesting(false) }
        } else if style == GlassStyle.clear.rawValue {
            content.glassEffect(.clear, in: shape)
        } else {
            content
                .background { CrystalFill(radius: radius, dark: scheme == .dark) }
                .overlay { shape.strokeBorder(edgeLight, lineWidth: 1).allowsHitTesting(false) }
        }
    }
    /// Light catches the top edge and fades towards the bottom, where a faint shade gives the pane depth.
    private var edgeLight: LinearGradient {
        let dark = scheme == .dark
        return LinearGradient(colors: [.white.opacity(dark ? 0.42 : 0.85), .white.opacity(dark ? 0.10 : 0.25), .white.opacity(0.05), .black.opacity(dark ? 0.35 : 0.08)],
                              startPoint: .top, endPoint: .bottom)
    }
}

/// The crystal pane: a blur of the backdrop, a tint that thins out downwards, and a sheen from the top-left.
private struct CrystalFill: View {
    let radius: CGFloat
    let dark: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let tint = dark ? Color(hex: 0x1A1B3A) : .white
        ZStack {
            // Light frosting: what is behind stays recognizable, the edge light and sheen make it glass.
            shape.fill(.ultraThinMaterial)
            shape.fill(LinearGradient(colors: [tint.opacity(dark ? 0.40 : 0.32), tint.opacity(dark ? 0.18 : 0.08)], startPoint: .top, endPoint: .bottom))
            shape.fill(RadialGradient(colors: [.white.opacity(dark ? 0.14 : 0.36), .white.opacity(0)], center: UnitPoint(x: 0.1, y: -0.1), startRadius: 0, endRadius: 460))
        }
        // The shadow belongs to the pane only; on the content it would shadow every line of text.
        .compositingGroup()
        .shadow(color: .black.opacity(dark ? 0.35 : 0.12), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func glassPanel(radius: CGFloat = 18) -> some View { modifier(GlassPanel(radius: radius)) }
    /// Groups content on non-list pages in a glass panel.
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 16)
    }
    /// A list or form that shows the glass it sits on instead of its own background.
    func glassList() -> some View {
        scrollContentBackground(.hidden)
            .glassPanel()
            .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
