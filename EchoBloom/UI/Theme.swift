import SwiftUI

/// Theatrical red-and-gold palette from the approved home-screen reference: hot scarlet
/// light, warm orange glow, gold actions, deep maroon glass and clean cream typography.
enum Theme {
    static let ink = Color(red: 0.15, green: 0.008, blue: 0.035)      // stage-curtain wine
    static let royal = Color(red: 0.92, green: 0.02, blue: 0.07)      // spotlight scarlet
    static let panel = Color(red: 0.30, green: 0.025, blue: 0.075)    // maroon glass
    static let glow = Color(red: 1.00, green: 0.47, blue: 0.08)       // hot orange light
    static let accent = Color(red: 1.00, green: 0.80, blue: 0.20)     // marquee gold
    static let accentDepth = Color(red: 0.88, green: 0.32, blue: 0.035) // orange button lip
    static let cream = Color(red: 1, green: 0.965, blue: 0.91)        // warm stage white
    static let stroke = accent.opacity(0.38)
    static let text = cream
    static let muted = cream.opacity(0.68)
    static let faint = cream.opacity(0.42)
    static let danger = Color(red: 1, green: 0.15, blue: 0.25)        // bright show red

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static let eyebrow = Font.system(size: 13, weight: .heavy, design: .rounded)
    static let body = Font.system(.body, design: .rounded, weight: .medium)
    static let label = Font.system(.headline, design: .rounded, weight: .bold)
}

/// The 3D stage's colors, matching `Theme`.
enum StageColors {
    typealias RGB = (CGFloat, CGFloat, CGFloat)
    static let skyTop: RGB = (0.20, 0.006, 0.025)
    static let skyHorizon: RGB = (0.98, 0.055, 0.095)
    static let skyBottom: RGB = (0.32, 0.012, 0.04)
    static let stageSide = UIColor(red: 0.52, green: 0.10, blue: 0.055, alpha: 1)
    static let stageTop = UIColor(red: 0.96, green: 0.34, blue: 0.065, alpha: 1)
    static let podium = UIColor(red: 0.26, green: 0.04, blue: 0.09, alpha: 1)
}

/// The layered show backdrop from the approved reference: deep wine edges, a hot scarlet
/// center, amber side spill, three overhead beams and the large crown silhouette.
struct TheaterBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(stops: [
                    .init(color: Color(red: 0.27, green: 0.005, blue: 0.045), location: 0),
                    .init(color: Color(red: 0.82, green: 0.018, blue: 0.085), location: 0.30),
                    .init(color: Color(red: 0.98, green: 0.055, blue: 0.075), location: 0.58),
                    .init(color: Color(red: 0.42, green: 0.012, blue: 0.045), location: 1),
                ], startPoint: .top, endPoint: .bottom)

                RadialGradient(colors: [
                    Theme.glow.opacity(0.82),
                    Color(red: 1, green: 0.16, blue: 0.04).opacity(0.34),
                    .clear,
                ], center: UnitPoint(x: 0.04, y: 0.48), startRadius: 0, endRadius: w * 0.58)

                RadialGradient(colors: [
                    Theme.glow.opacity(0.82),
                    Color(red: 1, green: 0.16, blue: 0.04).opacity(0.34),
                    .clear,
                ], center: UnitPoint(x: 0.96, y: 0.48), startRadius: 0, endRadius: w * 0.58)

                SpotlightShape(topLeft: 0.08, topRight: 0.24, bottomLeft: -0.07, bottomRight: 0.48)
                    .fill(LinearGradient(colors: [Theme.glow.opacity(0.38), Theme.glow.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: h * 0.66, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)

                SpotlightShape(topLeft: 0.76, topRight: 0.91, bottomLeft: 0.53, bottomRight: 1.08)
                    .fill(LinearGradient(colors: [Theme.glow.opacity(0.36), Theme.glow.opacity(0.07)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: h * 0.66, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)

                SpotlightShape(topLeft: 0.45, topRight: 0.57, bottomLeft: 0.29, bottomRight: 0.73)
                    .fill(LinearGradient(colors: [Theme.danger.opacity(0.32), Theme.glow.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: h * 0.58, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)

                CrownBackdropShape()
                    .fill(Color(red: 1, green: 0.10, blue: 0.18).opacity(0.29))
                    .frame(width: w * 0.56, height: h * 0.24)
                    .position(x: w * 0.5, y: h * 0.31)

                LinearGradient(colors: [.clear, Theme.ink.opacity(0.18)], startPoint: .center, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SpotlightShape: Shape {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomLeft: CGFloat
    let bottomRight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * topRight, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * bottomRight, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * bottomLeft, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CrownBackdropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let normalized: [CGPoint] = [
            CGPoint(x: 0.04, y: 0.88), CGPoint(x: 0.02, y: 0.27),
            CGPoint(x: 0.30, y: 0.61), CGPoint(x: 0.50, y: 0.04),
            CGPoint(x: 0.70, y: 0.61), CGPoint(x: 0.98, y: 0.27),
            CGPoint(x: 0.96, y: 0.88),
        ]
        let points = normalized.map { CGPoint(x: rect.width * $0.x, y: rect.height * $0.y) }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.addQuadCurve(to: points[0], control: CGPoint(x: rect.midX, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: Buttons

/// The main call to action: a candy-colored slab with a physical lip that presses down,
/// glowing softly in its own color.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var lip: Color? = nil
    var foreground: Color = Theme.ink
    var height: CGFloat = 62
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.uiScale) private var scale

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let depth: CGFloat = 6 * scale
        let height = self.height * scale
        configuration.label
            .scaledFont(size: self.height > 56 ? 20 : 17, weight: .black, design: .rounded)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
                    .fill(color)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    }
            }
            .offset(y: pressed ? depth - 1 : 0)
            .background {
                RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
                    .fill(lip ?? (color == Theme.accent ? Theme.accentDepth : color.mix(with: .black, by: 0.45)))
                    .offset(y: depth)
            }
            .padding(.bottom, depth)
            .shadow(color: color.opacity(isEnabled && !pressed ? 0.45 : 0), radius: 18 * scale, y: 6 * scale)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(pressed ? 0.985 : 1)
            .animation(.spring(duration: 0.18, bounce: 0.3), value: pressed)
    }
}

/// Secondary action on dark glass.
struct GlassButtonStyle: ButtonStyle {
    var height: CGFloat = 50
    var stroke: Color = Theme.stroke
    @Environment(\.uiScale) private var scale

    func makeBody(configuration: Configuration) -> some View {
        let height = self.height * scale
        return configuration.label
            .scaledFont(.headline, weight: .bold)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: height * 0.4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: height * 0.4, style: .continuous).strokeBorder(stroke, lineWidth: 1.25))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Round icon button used in top bars.
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(size: 17, weight: .bold, design: .default)
                .foregroundStyle(Theme.text)
                .frame(width: 46 * scale, height: 46 * scale)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

// MARK: Surfaces

struct GlassPanel: ViewModifier {
    var radius: CGFloat = 32
    @Environment(\.uiScale) private var scale

    func body(content: Content) -> some View {
        let radius = self.radius * scale
        return content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.panel.opacity(0.56)))
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke))
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func glassPanel(radius: CGFloat = 32) -> some View { modifier(GlassPanel(radius: radius)) }
}

/// Wine edge framing from the icon; keeps the eye on the middle without muddying the scene.
struct Vignette: View {
    var body: some View {
        RadialGradient(colors: [.clear, .clear, Theme.ink.opacity(0.46)], center: .center, startRadius: 120, endRadius: 620)
            .allowsHitTesting(false)
    }
}

/// Adds a ruby-wine base behind controls so they read clearly while the screen stays colorful.
struct BottomScrim: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Theme.ink.opacity(0.38), location: 0.45),
            .init(color: Theme.ink.opacity(0.82), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
    }
}

// MARK: Small pieces

struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased())
            .scaledFont(size: 13, weight: .heavy)
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

struct Pill: View {
    let text: String
    var color: Color = .white
    @Environment(\.uiScale) private var scale

    var body: some View {
        Text(text)
            .scaledFont(size: 13, weight: .heavy, design: .rounded)
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 14 * scale)
            .frame(height: 32 * scale)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .environment(\.colorScheme, .dark)
    }
}

struct PlayerDot: View {
    let color: BloomColor
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(color.color.gradient)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
    }
}

struct PlayerChip: View {
    let player: Player
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 8) {
            PlayerDot(color: player.color, size: 20 * scale)
            Text(player.name)
                .scaledFont(size: 15, weight: .bold, design: .rounded)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.text)
        .padding(.leading, 6 * scale)
        .padding(.trailing, 14 * scale)
        .frame(height: 34 * scale)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(player.color.color.opacity(0.6), lineWidth: 1.5))
        .environment(\.colorScheme, .dark)
    }
}

/// Vertical bars for live input or a prompt's loudness shape.
struct WaveBars: View {
    let values: [Double]
    var color: Color
    var progress: Double? = nil
    var minHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let gap: CGFloat = 3
            let width = max(2, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: gap) {
                ForEach(values.indices, id: \.self) { i in
                    let played = progress.map { Double(i) / Double(count) <= $0 } ?? true
                    Capsule()
                        .fill(played ? color : Color.white.opacity(0.18))
                        .frame(width: width, height: max(minHeight, geo.size.height * values[i]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.08), value: values)
    }
}

/// A notice that drops in from the top.
struct NoticeBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.bubble.fill")
            .scaledFont(.subheadline, weight: .bold)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassPanel(radius: 22)
            .padding(.horizontal, 20)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: iPad scaling

/// How much bigger the interface draws than its iPhone design size. It is exactly 1 on
/// every iPhone and in narrow iPad windows (Slide Over, small Split View), so those keep
/// the original design; full-size iPad windows get proportionally larger type, controls
/// and spacing instead of a stretched phone layout. Set once in `RootView`.
extension EnvironmentValues {
    @Entry var uiScale: CGFloat = 1
    /// Set only for wide iPad windows, where screens put their controls in a column of
    /// this width beside the stage. Always nil on iPhone.
    @Entry var sidePanelWidth: CGFloat? = nil
}

extension CGFloat {
    /// The iPad scale for a window size and its size classes.
    static func uiScale(for size: CGSize, roomy: Bool) -> CGFloat {
        guard roomy else { return 1 }
        // The design is drawn for roughly a 430 × 932 pt phone. Grow with whichever side
        // has less room, and stop before controls start to look inflated.
        let fit = Swift.min(size.width / 430, size.height / 900)
        return Swift.min(Swift.max(fit, 1), 1.32)
    }
}

/// A rounded system font whose size follows `uiScale`. At a scale of 1 it is the same
/// font the code used before, including Dynamic Type for text styles.
struct ScaledFont: ViewModifier {
    @Environment(\.uiScale) private var scale
    var size: CGFloat? = nil
    var style: Font.TextStyle? = nil
    var weight: Font.Weight? = nil
    var design: Font.Design = .rounded

    func body(content: Content) -> some View {
        content.font(font)
    }

    private var font: Font {
        if let size {
            return .system(size: size * scale, weight: weight ?? .regular, design: design)
        }
        let style = style ?? .body
        if scale == 1 {
            if let weight { return .system(style, design: design, weight: weight) }
            return .system(style, design: design)
        }
        let base = UIFont.preferredFont(forTextStyle: style.uiKit).pointSize
        return .system(size: base * scale, weight: weight ?? .regular, design: design)
    }
}

extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .black, design: Font.Design = .rounded) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }

    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFont(style: style, weight: weight))
    }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
