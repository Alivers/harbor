import SwiftUI
import AppKit

// Aurora Ice with hybrid glass, as in the design's E + 4 window (light) and its deep-indigo night version.
// Panes of crystal glass float over a harbor wallpaper; small floating controls use the system's clear Liquid Glass.
// Every value below comes from the design unless a comment says otherwise.

extension Color {
    /// Violet: tint, selection washes, brand icons and the primary button. White text on it passes 4.5:1 in both modes.
    static let harbor = Color(light: 0x6B5BFF, dark: 0x6656F0)
    /// Deep violet for small text on glass.
    static let harborText = Color(light: 0x4636D6, dark: 0xB3A9FF)
    /// Running, connected and success. The design marks them in the same deep violet as small text.
    static let harborLive = Color(light: 0x4636D6, dark: 0xB3A9FF)
    /// Body text: deep indigo by day, lilac white by night.
    static let harborInk = Color(light: 0x1B1638, dark: 0xF1EFFF)
    /// Secondary text, section labels and idle icons.
    static let harborSub = Color(light: 0x54506F, dark: 0xB9B4D9)

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

/// How the content panes are drawn. Floating controls always use the system's clear Liquid Glass.
enum GlassStyle: String, CaseIterable, Identifiable {
    /// Frosted crystal: the backdrop blurred and saturated under a lilac-white tint, with edge light and a sheen.
    case crystal = "Crystal"
    /// The system's clear Liquid Glass: barely blurred, so the wallpaper stays sharp.
    case clear = "Clear"
    var id: String { rawValue }
}

/// The coordinate space of the whole window, shared by the wallpaper and the panes that mirror it.
enum Backdrop { static let space = "harbor.backdrop" }

extension EnvironmentValues {
    /// Set inside a glass pane, so a panel within it draws as a lighter well instead of a second sheet of glass.
    @Entry var insidePane = false
}

/// The window's wallpaper: rows of corrugated containers under a soft glow, drawn from the window's top-left at a fixed
/// size, so resizing never redraws it and panes can mirror the part behind them.
struct Wallpaper: View {
    let dark: Bool
    /// As large as the largest screen (within reason), so the window never outgrows it.
    @MainActor static let size: CGSize = {
        let screens = NSScreen.screens.map(\.frame.size)
        let width = min(max(screens.map(\.width).max() ?? 0, 1600), 4096)
        let height = min(max(screens.map(\.height).max() ?? 0, 1000), 2560)
        return CGSize(width: width, height: height)
    }()
    var body: some View {
        Canvas { context, size in Self.draw(in: &context, size: size, palette: dark ? .dark : .light) }
            .frame(width: Self.size.width, height: Self.size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private struct Palette {
        let background: UInt32
        let glow: UInt32
        let blocks: [UInt32]
        let rib: Double
        let veil: Double
        /// The window's own faint tint over the desktop (rgba(t, .08) in the design).
        let wash: Color
        static let light = Palette(background: 0xE9EEFF, glow: 0xD5CCFF, blocks: [0xB9A8FF, 0x8CF0D0, 0xFFC7DD, 0xA8D8FF, 0x6B5BFF, 0xDCE6FF],
                                   rib: 0.13, veil: 0.12, wash: Color(hex: 0xFAF8FF).opacity(0.08))
        // Not in the design, which is light only: the same harbor at night in indigo, violet, teal and plum.
        static let dark = Palette(background: 0x0E1030, glow: 0x4B3BB8, blocks: [0x3D2F9E, 0x16806A, 0x8B3A68, 0x24589C, 0x6656F0, 0x232A5E],
                                  rib: 0.24, veil: 0.18, wash: Color(hex: 0x1A1B3A).opacity(0.10))
    }

    // Types are spelled out: mixed integer and CGFloat literals here are slow for the type checker.
    private static func draw(in context: inout GraphicsContext, size: CGSize, palette: Palette) {
        let bounds = CGRect(origin: .zero, size: size)
        let background: Color = Color(hex: palette.background)
        context.fill(Path(bounds), with: .color(background))
        // The design's window sits at (36, 30) on this desktop; drawing it shifted shows the window the same part.
        let glow: Color = Color(hex: palette.glow)
        let center = CGPoint(x: 764, y: 90)
        let circle = CGRect(x: center.x - 280, y: center.y - 280, width: 560, height: 560)
        context.fill(Path(ellipseIn: circle), with: .radialGradient(Gradient(colors: [glow, glow.opacity(0)]), center: center, startRadius: 0, endRadius: 277))
        drawBlocks(in: &context, size: size, palette: palette)
        context.fill(Path(bounds), with: .color(background.opacity(palette.veil)))
        context.fill(Path(bounds), with: .color(palette.wash))
    }
    private static func drawBlocks(in context: inout GraphicsContext, size: CGSize, palette: Palette) {
        let colors: [Color] = palette.blocks.map { Color(hex: $0) }
        let rib: Color = Color.black.opacity(palette.rib)
        let height: CGFloat = 54
        let rows: Int = Int((size.height + 30) / 62) + 1
        for r in 0..<rows {
            let y: CGFloat = CGFloat(r) * 62 - 22
            let start: Int = (r * 53) % 120
            var x: CGFloat = -CGFloat(start) - 36
            var i: Int = 0
            while x < size.width {
                let step: Int = (r * 31 + i * 47) % 4
                let width: CGFloat = CGFloat(120 + step * 30)
                if (r * 7 + i * 3) % 9 != 0 {
                    let block = CGRect(x: x, y: y, width: width, height: height)
                    let shape = Path(roundedRect: block, cornerRadius: 4)
                    context.fill(shape, with: .color(colors[(r * 3 + i * 5) % colors.count]))
                    // Corrugation: a 3 pt groove every 13 pt, starting 10 pt in.
                    var ribs = Path()
                    var groove: CGFloat = block.minX + 10
                    while groove < block.maxX {
                        ribs.addRect(CGRect(x: groove, y: block.minY, width: min(3, block.maxX - groove), height: height))
                        groove += 13
                    }
                    var inside = context
                    inside.clip(to: shape)
                    inside.fill(ribs, with: .color(rib))
                }
                x += width + 8
                i += 1
            }
        }
    }
}

/// Behind the wallpaper: the desktop, blurred by the window server. It shows only where the Background setting
/// thins the wallpaper out; with Reduce Transparency the window is solid.
struct WindowBackdrop: View {
    @AppStorage(Preference.backdropTint) private var tint = Preference.defaultBackdropTint
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency || tint >= 1 { Color(nsColor: .windowBackgroundColor) } else { DesktopBlur() }
    }
}

/// What lies behind the window, blurred by the window server.
struct DesktopBlur: NSViewRepresentable {
    var cornerRadius: CGFloat = 0
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        view.wantsLayer = true
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = cornerRadius > 0
    }
}

/// The wallpaper blurred and saturated the way the design's crystal glass treats its backdrop (blur 14, saturate 1.8),
/// rendered once per appearance. Each crystal pane draws the part behind it, which is what live glass would show
/// over a backdrop that never moves.
@MainActor @Observable final class BackdropCache {
    private var images: [Bool: NSImage] = [:]
    func image(dark: Bool) -> NSImage? { images[dark] }
    func prepare(dark: Bool) {
        guard images[dark] == nil else { return }
        let renderer = ImageRenderer(content: Wallpaper(dark: dark).blur(radius: 14, opaque: true).saturation(1.8))
        // The image is blurred, so half the resolution looks the same and costs a quarter of the memory.
        renderer.scale = 0.5
        images[dark] = renderer.nsImage
    }
}

/// The blurred wallpaper, placed so it lines up with the wallpaper behind the pane.
private struct BackdropMirror: View {
    let image: NSImage
    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .named(Backdrop.space)).origin
            Image(nsImage: image)
                .resizable()
                .frame(width: Wallpaper.size.width, height: Wallpaper.size.height)
                .offset(x: -origin.x, y: -origin.y)
        }
    }
}

/// A crystal pane's back: the blurred desktop (when the wallpaper lets it through), the mirrored wallpaper, then the glass.
private struct CrystalBackdrop: View {
    var radius: CGFloat
    @AppStorage(Preference.backdropTint) private var tint = Preference.defaultBackdropTint
    @Environment(\.colorScheme) private var scheme
    @Environment(BackdropCache.self) private var cache: BackdropCache?
    var body: some View {
        let dark = scheme == .dark
        ZStack {
            if tint < 1 { DesktopBlur(cornerRadius: radius) }
            if let image = cache?.image(dark: dark) { BackdropMirror(image: image).opacity(tint) }
            CrystalSurface(radius: radius, dark: dark)
        }
        .allowsHitTesting(false)
    }
}

/// The design's crystal recipe over the mirrored backdrop: a lilac-white gradient, an inner glow that is strongest at the
/// top, a sheen from the top-left, a bright line along the top edge, a faint shade along the bottom, a hairline border.
private struct CrystalSurface: View {
    var radius: CGFloat
    var dark: Bool
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let outline: Path = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
            context.clip(to: outline)
            drawFill(in: &context, size: size)
            drawGlow(in: &context, size: size)
            drawSheen(in: &context, size: size)
            drawEdges(in: &context, rect: rect)
        }
    }
    /// linear-gradient(160deg, tint .55, tint .24), with the gradient line spanning the corners as CSS does.
    private func drawFill(in context: inout GraphicsContext, size: CGSize) {
        let tint: Color = Color(hex: dark ? 0x1A1B3A : 0xFAF8FF)
        let dx: CGFloat = 0.342, dy: CGFloat = 0.940
        let half: CGFloat = (size.width * dx + size.height * dy) / 2
        let start = CGPoint(x: size.width / 2 - half * dx, y: size.height / 2 - half * dy)
        let end = CGPoint(x: size.width / 2 + half * dx, y: size.height / 2 + half * dy)
        let gradient = Gradient(colors: [tint.opacity(dark ? 0.62 : 0.55), tint.opacity(dark ? 0.38 : 0.24)])
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(gradient, startPoint: start, endPoint: end))
    }
    /// inset 0 22px 36px -28px white .7: the pane shrunk by 28, moved down 22 and blurred (σ 18) leaves a glow
    /// about 50 deep at the top, 28 at the sides and 6 at the bottom. Drawn as bands with the blur's falloff,
    /// combined in one layer so overlapping corners do not get brighter than the glow itself.
    private func drawGlow(in context: inout GraphicsContext, size: CGSize) {
        let w: CGFloat = size.width, h: CGFloat = size.height
        var glow = context
        glow.opacity = dark ? 0.35 : 0.7
        glow.drawLayer { layer in
            band(&layer, CGRect(x: 0, y: 0, width: w, height: 95), from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 95), Self.top)
            band(&layer, CGRect(x: 0, y: h - 54, width: w, height: 54), from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h - 54), Self.bottom)
            band(&layer, CGRect(x: 0, y: 0, width: 70, height: h), from: CGPoint(x: 0, y: 0), to: CGPoint(x: 70, y: 0), Self.side)
            band(&layer, CGRect(x: w - 70, y: 0, width: 70, height: h), from: CGPoint(x: w, y: 0), to: CGPoint(x: w - 70, y: 0), Self.side)
        }
    }
    // How much of each band the blurred glow covers, at even steps from the edge inwards.
    private static let top: [Double] = [1, 0.97, 0.85, 0.56, 0.23, 0.05, 0]
    private static let side: [Double] = [0.94, 0.78, 0.5, 0.22, 0.06, 0]
    private static let bottom: [Double] = [0.63, 0.39, 0.19, 0.07, 0.02, 0]
    private func band(_ context: inout GraphicsContext, _ rect: CGRect, from: CGPoint, to: CGPoint, _ coverage: [Double]) {
        let last = Double(coverage.count - 1)
        let stops: [Gradient.Stop] = coverage.enumerated().map { step in
            Gradient.Stop(color: Color.white.opacity(step.element), location: Double(step.offset) / last)
        }
        context.fill(Path(rect), with: .linearGradient(Gradient(stops: stops), startPoint: from, endPoint: to))
    }
    /// radial-gradient(130% 80% at 10% -10%, white .38, transparent 55%).
    private func drawSheen(in context: inout GraphicsContext, size: CGSize) {
        var sheen = context
        sheen.translateBy(x: size.width * 0.1, y: -size.height * 0.1)
        sheen.scaleBy(x: max(size.width * 1.3, 1), y: max(size.height * 0.8, 1))
        let gradient = Gradient(stops: [.init(color: .white.opacity(dark ? 0.16 : 0.38), location: 0), .init(color: .white.opacity(0), location: 0.55)])
        sheen.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)), with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1))
    }
    /// border 1px white .38; inset 0 0 0 1px white .18; inset 0 1px 0 white .85; inset 0 -1px 0 black .10.
    private func drawEdges(in context: inout GraphicsContext, rect: CGRect) {
        let border: Path = RoundedRectangle(cornerRadius: radius - 0.5, style: .continuous).path(in: rect.insetBy(dx: 0.5, dy: 0.5))
        context.stroke(border, with: .color(.white.opacity(dark ? 0.16 : 0.38)), lineWidth: 1)
        let inner: Path = RoundedRectangle(cornerRadius: max(radius - 1, 0), style: .continuous).path(in: rect.insetBy(dx: 1, dy: 1))
        var within = context
        within.clip(to: inner)
        let ring: Path = RoundedRectangle(cornerRadius: max(radius - 1.5, 0), style: .continuous).path(in: rect.insetBy(dx: 1.5, dy: 1.5))
        within.stroke(ring, with: .color(.white.opacity(dark ? 0.06 : 0.18)), lineWidth: 1)
        within.fill(crescent(inner, dy: 1), with: .color(.white.opacity(dark ? 0.42 : 0.85)), style: FillStyle(eoFill: true))
        within.fill(crescent(inner, dy: -1), with: .color(.black.opacity(dark ? 0.35 : 0.10)), style: FillStyle(eoFill: true))
    }
    /// The sliver between a shape and itself moved by `dy`: a line along the top (dy > 0) or the bottom (dy < 0).
    private func crescent(_ shape: Path, dy: CGFloat) -> Path {
        var path = shape
        path.addPath(shape.offsetBy(dx: 0, dy: dy))
        return path
    }
}

/// The pane's drop shadow (0 20px 48px black .26) as a Core Animation shadow with a fixed path, cut out under the pane
/// so it never darkens the glass. A blurred SwiftUI shadow would be redrawn on every frame of a resize or slide.
private struct PaneShadow: NSViewRepresentable {
    var radius: CGFloat
    var opacity: Float
    func makeNSView(context: Context) -> ShadowView { ShadowView() }
    func updateNSView(_ view: ShadowView, context: Context) {
        view.radius = radius; view.opacity = opacity
        view.needsLayout = true
    }
    final class ShadowView: NSView {
        var radius: CGFloat = 18
        var opacity: Float = 0.26
        private let caster = CALayer()
        private let cutout = CAShapeLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            let root = CALayer()
            root.masksToBounds = false
            layer = root
            wantsLayer = true
            caster.shadowColor = NSColor.black.cgColor
            caster.shadowRadius = 24
            caster.shadowOffset = CGSize(width: 0, height: -20)
            root.addSublayer(caster)
            cutout.fillRule = .evenOdd
            root.mask = cutout
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: bounds).cgPath
            caster.frame = bounds
            caster.shadowPath = shape
            caster.shadowOpacity = opacity
            let mask = CGMutablePath()
            mask.addRect(bounds.insetBy(dx: -120, dy: -120))
            mask.addPath(shape)
            cutout.frame = bounds
            cutout.path = mask
            CATransaction.commit()
        }
    }
}

/// A pane of glass in the chosen `GlassStyle`. Inside another pane it draws as a lighter well; with Reduce
/// Transparency it is solid.
struct GlassPanel: ViewModifier {
    var radius: CGFloat
    @AppStorage(Preference.glassStyle) private var style = GlassStyle.crystal.rawValue
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.insidePane) private var nested
    @ViewBuilder func body(content: Content) -> some View {
        let dark = scheme == .dark
        if nested {
            // A second sheet of glass would mirror the wallpaper again and read as a hole in the pane.
            let shape = RoundedRectangle(cornerRadius: min(radius, 12), style: .continuous)
            content
                .background(Color.white.opacity(dark ? 0.06 : 0.4), in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(dark ? 0.1 : 0.65)).allowsHitTesting(false) }
        } else {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if reduceTransparency {
                content
                    .environment(\.insidePane, true)
                    .background(Color(nsColor: .windowBackgroundColor), in: shape)
                    .overlay { shape.strokeBorder(Color.primary.opacity(0.12)).allowsHitTesting(false) }
            } else if style == GlassStyle.clear.rawValue {
                content
                    .environment(\.insidePane, true)
                    .glassEffect(.clear, in: shape)
                    .background { PaneShadow(radius: radius, opacity: dark ? 0.4 : 0.22) }
            } else {
                content
                    .environment(\.insidePane, true)
                    .background { CrystalBackdrop(radius: radius) }
                    .clipShape(shape)
                    .background { PaneShadow(radius: radius, opacity: dark ? 0.4 : 0.26) }
            }
        }
    }
}

extension View {
    func glassPanel(radius: CGFloat = 18) -> some View { modifier(GlassPanel(radius: radius)) }
    /// Groups content in a pane; inside another pane, in a lighter well.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel()
    }
    /// A pane only as tall as its content (up to the space there is), floating with the backdrop showing below.
    func huggingGlassPanel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            frame(maxWidth: .infinity).frame(maxHeight: height).glassPanel().layoutPriority(1)
            Spacer(minLength: 0)
        }
    }
}
