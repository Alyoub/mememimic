import SwiftUI

struct HandoffScreen: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        let player = game.currentPlayer
        Scaffold {
            MatchTopBar()
        } bottom: {
            VStack(spacing: 20 * scale) {
                VStack(spacing: 6 * scale) {
                    Eyebrow(text: game.players.count == 1 ? "Your turn" : "Pass the phone to")
                    Text(player.name)
                        .scaledFont(size: 52)
                        .foregroundStyle(Theme.accent)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .shadow(color: Theme.glow.opacity(0.55), radius: 20)
                    Text(prompt)
                        .scaledFont(.body, weight: .medium)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                TurnDots()
                Button(game.players.count == 1 ? "Let's go!" : "I'm \(player.name). Let's go!") { game.takeThePhone() }
                    .buttonStyle(ChunkyButtonStyle(height: 66))
                    .accessibilityIdentifier("handoff.go")
            }
        }
    }

    private var prompt: String {
        if game.players.count == 1 {
            return "Copy the sound and chase your best score."
        }
        return game.turn == 0 && game.round == 0
            ? "You're up first. Everyone else, get ready to judge."
            : "Your turn to make some noise."
    }
}

/// Round counter, current-player chip and quit control shared by in-match screens.
struct MatchTopBar: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        HStack {
            IconButton(symbol: "xmark", label: "Quit match") { game.askToQuit() }
            Spacer()
            Pill(text: "ROUND \(game.round + 1) OF \(game.roundsTotal)")
                .accessibilityIdentifier("round.label")
            Spacer()
            MuteButton()
        }
    }
}

/// One dot per player this round: done, current, or waiting.
struct TurnDots: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        HStack(spacing: 8 * scale) {
            ForEach(0..<game.players.count, id: \.self) { i in
                let player = game.players[(i + game.round) % game.players.count]
                let done = game.roundResults[player.id] != nil
                let current = i == game.turn && !done
                Capsule()
                    .fill(done || current ? Theme.accent : .white.opacity(0.18))
                    .frame(width: current ? 28 * scale : 10 * scale, height: 10 * scale)
                    .opacity(done ? 0.55 : 1)
            }
        }
        .animation(.spring(duration: 0.4), value: game.turn)
        .accessibilityElement()
        .accessibilityLabel("Turn \(game.turn + 1) of \(game.players.count)")
    }
}

/// The game's own quit confirmation: a centred card over a dimmed screen. (The system
/// confirmation dialog shows as a small bubble by the ✕ on recent iOS, easy to miss.)
struct QuitPanel: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { game.keepPlaying() }
                .accessibilityHidden(true)
            VStack(spacing: 16 * scale) {
                Image(systemName: "door.left.hand.open")
                    .scaledFont(size: 30, weight: .bold, design: .default)
                    .foregroundStyle(Theme.danger)
                VStack(spacing: 6 * scale) {
                    Text("Quit this match?")
                        .scaledFont(size: 26)
                        .foregroundStyle(Theme.text)
                    Text("Scores from this match will be lost.")
                        .scaledFont(.body, weight: .medium)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 10 * scale) {
                    Button("Quit match") { game.confirmQuit() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.danger, foreground: .white, height: 56))
                        .accessibilityIdentifier("quit.confirm")
                    Button("Keep playing") { game.keepPlaying() }
                        .buttonStyle(GlassButtonStyle())
                        .accessibilityIdentifier("quit.cancel")
                }
            }
            .padding(24 * scale)
            .glassPanel()
            .padding(.horizontal, 28 * scale)
            .frame(maxWidth: 440 * scale)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .accessibilityAddTraits(.isModal)
    }
}
