import SwiftUI

struct RevealScreen: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var barsIn = false

    var body: some View {
        let result = game.lastResult ?? TurnResult(total: 0, pitch: 0, rhythm: 0, length: 0, isDemo: true)
        let player = game.currentPlayer
        Scaffold {
            MatchTopBar()
        } bottom: {
            VStack(spacing: 14 * scale) {
                VStack(spacing: 14 * scale) {
                    HStack {
                        PlayerChip(player: player)
                        Spacer()
                        if result.isDemo {
                            Pill(text: "DEMO SCORE", color: Theme.accent)
                        } else if let rank = game.roundRankOfLastResult, game.roundResults.count > 1 {
                            Pill(text: rank == 1 ? "BEST THIS ROUND" : "#\(rank) THIS ROUND", color: rank == 1 ? Theme.accent : Theme.text)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                        Text("\(shown)")
                            .scaledFont(size: 96)
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText(value: Double(shown)))
                            .shadow(color: Theme.glow.opacity(0.55), radius: 22)
                            .monospacedDigit()
                        Text("/100")
                            .scaledFont(size: 22)
                            .foregroundStyle(Theme.faint)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Score \(result.total) out of 100")
                    .accessibilityIdentifier("score")

                    Text(result.verdict)
                        .scaledFont(size: 22)
                        .foregroundStyle(Theme.text)
                        .opacity(shown == result.total ? 1 : 0)
                        .scaleEffect(shown == result.total ? 1 : 0.85)

                    VStack(spacing: 10 * scale) {
                        Breakdown(title: "Pitch", value: result.pitch, color: Theme.accent, show: barsIn)
                        Breakdown(title: "Rhythm", value: result.rhythm, color: Theme.glow, show: barsIn)
                        Breakdown(title: "Length", value: result.length, color: Theme.accent, show: barsIn)
                    }

                    if !result.isDemo {
                        HStack(spacing: 10 * scale) {
                            Button { game.replayTake() } label: { Label("Your take", systemImage: "play.fill") }
                                .buttonStyle(GlassButtonStyle(height: 44))
                            Button { game.replayPrompt() } label: { Label("Original", systemImage: "speaker.wave.2.fill") }
                                .buttonStyle(GlassButtonStyle(height: 44))
                        }
                    }
                }
                .padding(20 * scale)
                .glassPanel()

                Button(game.nextPlayer.map { "Pass to \($0.name)" } ?? "See round results") {
                    game.continueAfterReveal()
                }
                .buttonStyle(ChunkyButtonStyle(height: 64))
                .accessibilityIdentifier("reveal.next")
            }
        }
        .task { await countUp(to: result.total) }
    }

    private func countUp(to total: Int) async {
        if reduceMotion || game.isUITesting {
            shown = total
            barsIn = true
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        let steps = 28
        for i in 1...steps {
            let eased = 1 - pow(1 - Double(i) / Double(steps), 3)
            withAnimation(.snappy(duration: 0.08)) { shown = Int((Double(total) * eased).rounded()) }
            if i % 3 == 0 { Haptics.tick() }
            try? await Task.sleep(for: .milliseconds(28 + i * 2))
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.5)) { shown = total }
        total >= 62 ? Haptics.success() : Haptics.thump()
        withAnimation(.spring(duration: 0.7, bounce: 0.2)) { barsIn = true }
    }
}

private struct Breakdown: View {
    @Environment(\.uiScale) private var scale
    let title: String
    let value: Int
    let color: Color
    let show: Bool

    var body: some View {
        HStack(spacing: 12 * scale) {
            Text(title)
                .scaledFont(size: 14, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.muted)
                .frame(width: 58 * scale, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(LinearGradient(colors: [Theme.glow, Theme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: show ? max(10 * scale, geo.size.width * Double(value) / 100 * scale) : 10 * scale)
                }
            }
            .frame(height: 10 * scale)
            Text("\(value)")
                .scaledFont(size: 14, weight: .heavy, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(width: 30 * scale, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}
