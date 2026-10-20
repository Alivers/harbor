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
    /// The system's frosted Liquid Glass, lightly tinted, with a bright edge and a top sheen.
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
        // Glass is only visible over detail: blurring a smooth gradient changes nothing.
        .overlay { HarborScape(dark: scheme == .dark) }
    }
    // Ice, lilac and mint by day; indigo, violet and deep teal by night. Saturated enough to read as color once it is a tint.
    private static let light: [UInt32] = [0xDCE4FF, 0xC2B4FF, 0xB3D8FF, 0xEAE6FF, 0xD3DBFF, 0xA9EDD6, 0xFFD0E2, 0xDDE6FF, 0xCBC0FF]
    private static let dark: [UInt32] = [0x0E1030, 0x2E2378, 0x0E2A52, 0x121433, 0x191C46, 0x0D4A45, 0x35195A, 0x101333, 0x271F6E]
}

/// Rows of corrugated containers and two waves, as in the app icon, drawn faintly in the aurora's colors.
/// They give the glass panels edges to blur and bend; they fade towards the top, where most text sits.
private struct HarborScape: View {
    let dark: Bool
    private static let lightColors: [UInt32] = [0xB6A8FF, 0xA9CCFF, 0x9EE8CF, 0xFFC3DA, 0xD6CCFF, 0xC9D8FF]
    private static let darkColors: [UInt32] = [0x3A2E8C, 0x1E3E70, 0x155E57, 0x5A2A6E, 0x2A2468, 0x1B2150]
    private static let blockHeight: CGFloat = 46
    private static let gap: CGFloat = 8
    var body: some View {
        Canvas { context, size in
            drawContainers(in: &context, size: size)
            drawWaves(in: &context, size: size)
        }
        .allowsHitTesting(false)
    }
    // Types are spelled out: mixed integer and CGFloat literals here are slow for the type checker.
    private func drawContainers(in context: inout GraphicsContext, size: CGSize) {
        let colors: [Color] = (dark ? Self.darkColors : Self.lightColors).map { Color(hex: $0) }
        let pitch: CGFloat = Self.blockHeight + Self.gap
        let rows: Int = Int(size.height / pitch) + 1
        let ribShade: Double = dark ? 0.2 : 0.07
        for r in 0..<rows {
            let y: CGFloat = 6 + CGFloat(r) * pitch
            // Fainter higher up: 0.25 at the top, 0.9 at the bottom.
            let depth: Double = Double(y / max(size.height, 1))
            let alpha: Double = 0.25 + 0.65 * depth
            let offset: Int = (r * 53) % 120
            var x: CGFloat = -CGFloat(offset)
            var i: Int = 0
            while x < size.width {
                let widthStep: Int = (r * 31 + i * 47) % 4
                let width: CGFloat = CGFloat(120 + widthStep * 30)
                if (r * 7 + i * 3) % 9 != 0 {
                    let block = CGRect(x: x, y: y, width: width, height: Self.blockHeight)
                    let color: Color = colors[(r * 3 + i * 5) % colors.count]
                    context.fill(Path(roundedRect: block, cornerRadius: 5), with: .color(color.opacity(alpha)))
                    var rib: CGFloat = block.minX + 10
                    while rib < block.maxX - 8 {
                        let ribRect = CGRect(x: rib, y: block.minY + 8, width: 3, height: Self.blockHeight - 16)
                        context.fill(Path(ribRect), with: .color(Color.black.opacity(ribShade * alpha)))
                        rib += 13
                    }
                }
                x += width + Self.gap
                i += 1
            }
        }
    }
    private func drawWaves(in context: inout GraphicsContext, size: CGSize) {
        let white: Color = Color.white.opacity(dark ? 0.16 : 0.55)
        let mint: Color = Color(hex: dark ? 0x5EE6B5 : 0x8CF0D0).opacity(dark ? 0.22 : 0.5)
        let waves: [Color] = [white, mint]
        let amplitude: CGFloat = 12
        for (k, color) in waves.enumerated() {
            let base: CGFloat = size.height * (0.44 + 0.05 * CGFloat(k))
            let phase: CGFloat = CGFloat(k) * 1.9
            var wave = Path()
            for step in 0...120 {
                let t: CGFloat = CGFloat(step) / 120
                let angle: CGFloat = t * 4 * CGFloat.pi + phase
                let point = CGPoint(x: size.width * t, y: base + amplitude * sin(angle))
                if step == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
            }
            context.stroke(wave, with: .color(color), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        }
    }
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
            // Real Liquid Glass: it blurs and bends what is behind it and catches light at the edge.
            // The sheen sits between the glass and the content; the edge light goes on top.
            content
                .background { shape.fill(sheen) }
                .glassEffect(.regular.tint(scheme == .dark ? Color(hex: 0x1A1B3A).opacity(0.28) : Color.white.opacity(0.12)), in: shape)
                .overlay { shape.strokeBorder(edgeLight, lineWidth: 1).allowsHitTesting(false) }
        }
    }
    private var sheen: RadialGradient {
        RadialGradient(colors: [.white.opacity(scheme == .dark ? 0.12 : 0.32), .white.opacity(0)], center: UnitPoint(x: 0.1, y: -0.1), startRadius: 0, endRadius: 460)
    }
    /// Light catches the top edge and fades towards the bottom, where a faint shade gives the pane depth.
    private var edgeLight: LinearGradient {
        let dark = scheme == .dark
        return LinearGradient(colors: [.white.opacity(dark ? 0.42 : 0.85), .white.opacity(dark ? 0.10 : 0.25), .white.opacity(0.05), .black.opacity(dark ? 0.35 : 0.08)],
                              startPoint: .top, endPoint: .bottom)
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
    /// A glass panel only as tall as its content (up to the space there is), with the backdrop showing below.
    /// A panel stretched over the whole page reads as a background, not as a pane of glass.
    func huggingGlassPanel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            frame(maxWidth: .infinity).frame(maxHeight: height).glassPanel().layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
