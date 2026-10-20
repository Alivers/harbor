import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The picture behind the panes. Harbor draws it itself because glass needs color and shape behind it: over a plain or
// white background every glass recipe reads as a white card. Each pane shows a pre-blurred copy of the part behind
// it, which is what glass with the design's blur would show, using only public API.

/// What the window shows behind its panes.
enum BackdropStyle: String, CaseIterable, Identifiable {
    /// Soft blocks of violet, mint, pink and ice blue, in the Aurora Ice palette. The default.
    case aurora = "Aurora"
    /// The design mockup's harbor of corrugated containers.
    case harbor = "Harbor"
    /// The current desktop picture, lined up with the screen as if the window were clear.
    case desktop = "Desktop Picture"
    /// A picture the user chooses, laid out on the screen like a desktop picture.
    case custom = "Custom Picture"
    var id: String { rawValue }
    /// Pictures stay put on the screen while the window moves; drawn backdrops move with the window.
    var followsScreen: Bool { self == .desktop || self == .custom }
}

/// The window's backdrop: its style, its picture, where it sits relative to the window, and the blurred copy the
/// panes show through their glass.
@MainActor @Observable final class Backdrop {
    static let space = "harbor.backdrop"
    /// Drawn backdrops are as large as the largest screen (within reason), so resizing never redraws them.
    static let largest: CGSize = {
        let screens = NSScreen.screens.map(\.frame.size)
        let width = min(max(screens.map(\.width).max() ?? 0, 1600), 4096)
        let height = min(max(screens.map(\.height).max() ?? 0, 1000), 2560)
        return CGSize(width: width, height: height)
    }()

    private(set) var style: BackdropStyle
    private(set) var picture: NSImage? = nil
    /// The custom picture's file, if one was chosen.
    private(set) var picturePath: String?
    /// The backdrop's size, and where its top-left corner sits relative to the window's.
    private(set) var size: CGSize = Backdrop.largest
    private(set) var origin: CGPoint = .zero
    /// The backdrop blurred and saturated for the current glass style.
    private(set) var mirror: NSImage? = nil
    /// Changes whenever what the backdrop shows changes, so the mirror is rendered again.
    private(set) var revision = 0
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var desktopURL: URL? = nil

    init() {
        let defaults = UserDefaults.standard
        style = defaults.string(forKey: Preference.backdrop).flatMap(BackdropStyle.init(rawValue:)) ?? .aurora
        picturePath = defaults.string(forKey: Preference.backdropPicture)
    }

    func select(_ style: BackdropStyle) {
        if style == .custom && picturePath == nil { choosePicture(); return }
        self.style = style
        UserDefaults.standard.set(style.rawValue, forKey: Preference.backdrop)
        desktopURL = nil
        picture = nil
        if style.followsScreen, let window { follow(window) } else { size = Backdrop.largest; origin = .zero }
        revision += 1
    }
    /// Asks for a picture and shows it; cancelling keeps the current backdrop.
    func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a picture to show behind Harbor's panes."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        picturePath = url.path
        UserDefaults.standard.set(url.path, forKey: Preference.backdropPicture)
        select(.custom)
    }

    /// Lines a picture backdrop up with the window's screen. Called when the window moves, resizes, changes screens or
    /// becomes key, which is also when a changed desktop picture is picked up.
    func follow(_ window: NSWindow) {
        self.window = window
        guard style.followsScreen, let screen = window.screen ?? NSScreen.main else { return }
        let offset = CGPoint(x: screen.frame.minX - window.frame.minX, y: window.frame.maxY - screen.frame.maxY)
        if offset != origin { origin = offset }
        var changed = false
        if screen.frame.size != size { size = screen.frame.size; changed = true }
        let url = style == .desktop ? NSWorkspace.shared.desktopImageURL(for: screen) : picturePath.map { URL(fileURLWithPath: $0) }
        if url != desktopURL {
            desktopURL = url
            // A missing or unreadable picture (a video wallpaper, a moved file) falls back to the aurora.
            picture = url.flatMap { NSImage(contentsOf: $0) }
            changed = true
        }
        if changed { revision += 1 }
    }

    /// Renders the copy the panes show: blur 2.5 and saturation 1.6 for clear glass, blur 14 and 1.8 for crystal.
    func renderMirror(dark: Bool, glass: GlassStyle) {
        let crystal = glass == .crystal
        let content = BackdropContent(style: style, picture: picture, size: size, dark: dark)
            .blur(radius: crystal ? 14 : 2.5, opaque: true)
            .saturation(crystal ? 1.8 : 1.6)
        let renderer = ImageRenderer(content: content)
        // A strong blur hides a lower resolution and saves three quarters of the memory.
        renderer.scale = crystal ? 0.5 : 1
        mirror = renderer.nsImage
    }
}

/// The backdrop as the window shows it, behind everything.
struct BackdropView: View {
    @Environment(Backdrop.self) private var backdrop
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        BackdropContent(style: backdrop.style, picture: backdrop.picture, size: backdrop.size, dark: scheme == .dark)
            .offset(x: backdrop.origin.x, y: backdrop.origin.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The part of the blurred backdrop behind a pane, lined up with the backdrop around it.
struct BackdropMirror: View {
    @Environment(Backdrop.self) private var backdrop: Backdrop?
    var body: some View {
        if let backdrop, let image = backdrop.mirror {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(Backdrop.space))
                Image(nsImage: image)
                    .resizable()
                    .frame(width: backdrop.size.width, height: backdrop.size.height)
                    .offset(x: backdrop.origin.x - frame.minX, y: backdrop.origin.y - frame.minY)
            }
        }
    }
}

/// The backdrop's picture at its full size.
struct BackdropContent: View {
    let style: BackdropStyle
    let picture: NSImage?
    let size: CGSize
    let dark: Bool
    var body: some View {
        Group {
            if style.followsScreen, let picture {
                Image(nsImage: picture).resizable().aspectRatio(contentMode: .fill)
            } else if style == .harbor {
                Canvas { context, size in HarborPainter.draw(in: &context, size: size, dark: dark) }
            } else {
                Canvas { context, size in AuroraPainter.draw(in: &context, size: size, dark: dark) }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// Watches the window so picture backdrops stay lined up with the screen.
struct BackdropTracker: NSViewRepresentable {
    let backdrop: Backdrop
    func makeNSView(context: Context) -> TrackerView { TrackerView(backdrop: backdrop) }
    func updateNSView(_ view: TrackerView, context: Context) {}

    final class TrackerView: NSView {
        private let backdrop: Backdrop
        private var observers: [NSObjectProtocol] = []
        init(backdrop: Backdrop) { self.backdrop = backdrop; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                                              NSWindow.didChangeScreenNotification, NSWindow.didBecomeKeyNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sync() }
                })
            }
            sync()
        }
        private func sync() { if let window { backdrop.follow(window) } }
    }
}

/// Soft blocks of color in the Aurora Ice palette: circles and pills with crisp edges, so the glass has shapes to bend.
private enum AuroraPainter {
    /// x, y, width, height, corner radius (half the height for a pill), rotation in degrees, color index.
    private typealias Block = (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Double, Int)
    /// One 1600 × 1000 tile, repeated for larger windows.
    private static let tile = CGSize(width: 1600, height: 1000)
    private static let blocks: [Block] = [
        (40, 10, 300, 300, 150, 0, 0),
        (330, -90, 560, 210, 105, 12, 1),
        (800, 30, 380, 380, 190, 0, 3),
        (1160, -40, 480, 200, 100, -10, 2),
        (-60, 360, 640, 190, 95, -12, 2),
        (620, 380, 270, 270, 135, 0, 4),
        (960, 400, 470, 300, 70, 8, 1),
        (1380, 330, 330, 330, 165, 0, 0),
        (120, 640, 400, 400, 200, 0, 3),
        (560, 760, 700, 200, 100, -6, 0),
        (1200, 700, 460, 460, 230, 0, 2),
        (900, 620, 200, 200, 100, 0, 5)]
    private static let light: [UInt32] = [0xB9A8FF, 0x8CF0D0, 0xFFC7DD, 0xA8D8FF, 0x6B5BFF, 0xDCE6FF]
    private static let dark: [UInt32] = [0x3D2F9E, 0x16806A, 0x8B3A68, 0x24589C, 0x6656F0, 0x232A5E]

    static func draw(in context: inout GraphicsContext, size: CGSize, dark: Bool) {
        let background: Color = Color(hex: dark ? 0x0E1030 : 0xE9EEFF)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
        let colors: [Color] = (dark ? Self.dark : Self.light).map { Color(hex: $0) }
        let columns: Int = Int(size.width / tile.width) + 1
        let rows: Int = Int(size.height / tile.height) + 1
        for row in 0..<rows {
            for column in 0..<columns {
                let origin = CGPoint(x: CGFloat(column) * tile.width, y: CGFloat(row) * tile.height)
                for block in blocks { drawBlock(block, at: origin, in: &context, colors: colors, dark: dark) }
            }
        }
        // The design's veil softens everything a little towards the background.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background.opacity(dark ? 0.18 : 0.12)))
    }
    private static func drawBlock(_ block: Block, at origin: CGPoint, in context: inout GraphicsContext, colors: [Color], dark: Bool) {
        let (x, y, width, height, radius, degrees, index) = block
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        var layer = context
        layer.translateBy(x: origin.x + x + width / 2, y: origin.y + y + height / 2)
        layer.rotate(by: .degrees(degrees))
        layer.translateBy(x: -width / 2, y: -height / 2)
        let color: Color = colors[index % colors.count]
        // Lighter towards the top-left, like light falling across the color.
        let gradient = Gradient(colors: [color.mix(with: .white, by: dark ? 0.12 : 0.35), color])
        layer.fill(Path(roundedRect: rect, cornerRadius: radius),
                   with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: width, y: height)))
    }
}

/// The design mockup's harbor: rows of corrugated containers under a soft glow.
private enum HarborPainter {
    private static let light: [UInt32] = [0xB9A8FF, 0x8CF0D0, 0xFFC7DD, 0xA8D8FF, 0x6B5BFF, 0xDCE6FF]
    private static let dark: [UInt32] = [0x3D2F9E, 0x16806A, 0x8B3A68, 0x24589C, 0x6656F0, 0x232A5E]

    // Types are spelled out: mixed integer and CGFloat literals here are slow for the type checker.
    static func draw(in context: inout GraphicsContext, size: CGSize, dark: Bool) {
        let bounds = CGRect(origin: .zero, size: size)
        let background: Color = Color(hex: dark ? 0x0E1030 : 0xE9EEFF)
        context.fill(Path(bounds), with: .color(background))
        // The design's window sits at (36, 30) on this desktop; drawing it shifted shows the window the same part.
        let glow: Color = Color(hex: dark ? 0x4B3BB8 : 0xD5CCFF)
        let center = CGPoint(x: 764, y: 90)
        let circle = CGRect(x: center.x - 280, y: center.y - 280, width: 560, height: 560)
        context.fill(Path(ellipseIn: circle), with: .radialGradient(Gradient(colors: [glow, glow.opacity(0)]), center: center, startRadius: 0, endRadius: 277))
        drawBlocks(in: &context, size: size, dark: dark)
        context.fill(Path(bounds), with: .color(background.opacity(dark ? 0.18 : 0.12)))
    }
    private static func drawBlocks(in context: inout GraphicsContext, size: CGSize, dark: Bool) {
        let colors: [Color] = (dark ? Self.dark : Self.light).map { Color(hex: $0) }
        let rib: Color = Color.black.opacity(dark ? 0.24 : 0.13)
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
