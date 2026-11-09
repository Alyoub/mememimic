import SwiftUI

/// Animated launch screen built around the app icon. It also covers the few seconds the
/// 3D stage takes to load, then zooms through into the home screen.
///
/// Sequence: the icon springs in, rings pulse out and a shine sweeps across it, the
/// wordmark pops in letter by letter, then the tagline. It leaves once the stage is ready
/// (and at least `minimumTime` has passed, so it never flickers).
struct SplashView: View {
    @Environment(GameModel.self) private var game
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var iconIn = false
    @State private var shine = false
    @State private var pulse = 0
    @State private var letters = 0
    @State private var taglineIn = false
    @State private var waiting = false
    @State private var exiting = false

    private let title = Array("MEME MIMIC")
    private let iconSize: CGFloat = 168
    private let minimumTime = 2.3
    private let maximumWait = 9.0

    var body: some View {
        ZStack {
            background
            VStack(spacing: 28) {
                ZStack {
                    PulseRings(trigger: pulse, reduceMotion: reduceMotion)
                        .frame(width: iconSize, height: iconSize)
                    icon
                }
                wordmark
                Text("Copy the sound. Win the room.")
                    .scaledFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.muted)
                    .opacity(taglineIn ? 1 : 0)
                    .offset(y: taglineIn ? 0 : 8)
            }
            .offset(y: -20)

            LoadingDots()
                .opacity(waiting && !exiting ? 1 : 0)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 70)
        }
        .scaleEffect(exiting ? 1.08 : 1)
        .opacity(exiting ? 0 : 1)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meme Mimic. Loading.")
        .task { await run() }
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            Theme.ink
            RadialGradient(colors: [Theme.royal, Theme.royal.opacity(0.55), Theme.ink],
                           center: .center, startRadius: 30, endRadius: 560)
                .opacity(iconIn ? 1 : 0.4)
            if !reduceMotion {
                LightRays()
                    .opacity(iconIn ? 0.55 : 0)
                Sparkles()
            }
        }
        .animation(.easeOut(duration: 0.9), value: iconIn)
    }

    private var icon: some View {
        let shape = RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous)
        return Image("SplashIcon")
            .resizable()
            .interpolation(.high)
            .frame(width: iconSize, height: iconSize)
            .overlay {
                // A bright band that sweeps across once, like light catching the glaze.
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.45)
                        .rotationEffect(.degrees(20))
                        .offset(x: shine ? geo.size.width * 1.3 : -geo.size.width * 0.8)
                        .blendMode(.plusLighter)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: Theme.glow.opacity(iconIn ? 0.6 : 0), radius: 34)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
            .scaleEffect(iconIn ? 1 : 0.55)
            .rotationEffect(.degrees(iconIn || reduceMotion ? 0 : -8))
            .opacity(iconIn ? 1 : 0)
            .scaleEffect(exiting ? 1.25 : 1)
    }

    private var wordmark: some View {
        HStack(spacing: 2) {
            ForEach(title.indices, id: \.self) { i in
                Text(String(title[i]))
                    .scaledFont(size: 34, weight: .black, design: .rounded)
                    .tracking(2)
                    .foregroundStyle(Theme.cream)
                    .opacity(i < letters ? 1 : 0)
                    .offset(y: i < letters ? 0 : 18)
                    .scaleEffect(i < letters ? 1 : 0.6)
            }
        }
        .shadow(color: Theme.glow.opacity(0.35), radius: 12)
    }

    // MARK: Timeline

    private func run() async {
        let start = Date()
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) { iconIn = true; letters = title.count; taglineIn = true }
        } else {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(duration: 0.7, bounce: 0.45)) { iconIn = true }
            try? await Task.sleep(for: .milliseconds(420))
            Haptics.tap()
            pulse += 1
            withAnimation(.easeInOut(duration: 0.9)) { shine = true }
            for i in 1...title.count {
                withAnimation(.spring(duration: 0.35, bounce: 0.5)) { letters = i }
                try? await Task.sleep(for: .milliseconds(55))
            }
            withAnimation(.easeOut(duration: 0.5)) { taglineIn = true }
        }

        // Hold until the stage is ready, pulsing gently while we wait.
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            if (game.stageReady && elapsed >= minimumTime) || elapsed >= maximumWait { break }
            if elapsed >= minimumTime, !waiting { withAnimation(.easeIn(duration: 0.3)) { waiting = true } }
            if !reduceMotion, Int(elapsed * 10) % 14 == 0 { pulse += 1 }
            try? await Task.sleep(for: .milliseconds(100))
        }

        withAnimation(.easeIn(duration: 0.45)) { exiting = true }
        try? await Task.sleep(for: .milliseconds(450))
        game.finishSplash()
    }
}

/// Cyan rings that ripple out from behind the icon each time `trigger` changes.
private struct PulseRings: View {
    let trigger: Int
    let reduceMotion: Bool
    @State private var rings: [Int] = []

    var body: some View {
        ZStack {
            ForEach(rings, id: \.self) { id in
                Ring()
            }
        }
        .onChange(of: trigger) { _, new in
            guard !reduceMotion else { return }
            rings.append(new)
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                rings.removeAll { $0 == new }
            }
        }
    }

    private struct Ring: View {
        @State private var grown = false

        var body: some View {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(Theme.glow, lineWidth: 3)
                .scaleEffect(grown ? 2.1 : 1)
                .opacity(grown ? 0 : 0.8)
                .onAppear { withAnimation(.easeOut(duration: 1.3)) { grown = true } }
        }
    }
}

/// Slowly turning beams of light behind the icon.
private struct LightRays: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
                let length = max(size.width, size.height)
                let count = 12
                for i in 0..<count {
                    let angle = Double(i) / Double(count) * 2 * .pi + t * 0.12
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x + cos(angle - 0.09) * length, y: center.y + sin(angle - 0.09) * length))
                    path.addLine(to: CGPoint(x: center.x + cos(angle + 0.09) * length, y: center.y + sin(angle + 0.09) * length))
                    path.closeSubpath()
                    ctx.fill(path, with: .radialGradient(Gradient(colors: [Theme.glow.opacity(0.35), .clear]),
                                                         center: center, startRadius: 40, endRadius: length * 0.6))
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// Small glints drifting upward, in the icon's colors.
private struct Sparkles: View {
    private struct Mote { let x, speed, size, phase: Double; let color: Color }
    private let motes: [Mote] = (0..<28).map { i in
        let r = Double((i * 7919) % 1000) / 1000
        let colors = [Theme.glow, Theme.cream, Theme.accent]
        return Mote(x: Double((i * 3571) % 1000) / 1000, speed: 0.03 + r * 0.05, size: 2 + r * 3,
                    phase: Double((i * 1237) % 1000) / 1000, color: colors[i % colors.count])
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for m in motes {
                    let y = 1 - ((m.phase + t * m.speed).truncatingRemainder(dividingBy: 1))
                    let twinkle = 0.4 + 0.6 * abs(sin(t * 2 + m.phase * 10))
                    let rect = CGRect(x: m.x * size.width, y: y * size.height, width: m.size, height: m.size)
                    ctx.fill(Path(ellipseIn: rect), with: .color(m.color.opacity(twinkle * 0.8)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Three bouncing dots in the logo colors, shown only if loading takes a while.
private struct LoadingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 10) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill([Theme.glow, Theme.cream, Theme.accent][i])
                        .frame(width: 10, height: 10)
                        .offset(y: -abs(sin(t * 5 + Double(i) * 0.6)) * 8)
                }
            }
        }
    }
}
