import SwiftUI

struct RecapScreen: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game
    @EnvironmentObject private var ads: AdsManager
    @State private var appeared = false

    var body: some View {
        Scaffold {
            MatchTopBar()
        } bottom: {
            VStack(spacing: 14 * scale) {
                VStack(spacing: 4 * scale) {
                    Eyebrow(text: "Round \(game.round + 1) complete", color: Theme.accent)
                    Text(headline)
                        .scaledFont(size: 30)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 6 * scale) {
                    ForEach(Array(game.standings.enumerated()), id: \.element.player.id) { index, entry in
                        StandingRow(rank: entry.rank,
                                    player: entry.player,
                                    roundScore: game.roundResults[entry.player.id]?.total,
                                    change: game.rankChange(for: entry.player, now: entry.rank))
                            .opacity(appeared ? 1 : 0)
                            .offset(x: appeared ? 0 : 30 * scale)
                            .animation(.spring(duration: 0.5, bounce: 0.25).delay(Double(index) * 0.06), value: appeared)
                    }
                }
                .padding(10 * scale)
                .glassPanel()

                Button(game.isLastRound ? "Reveal the winner" : "Start round \(game.round + 2)") {
                    if game.isLastRound {
                        ads.showRewarded { _ in game.continueAfterRecap() }
                    } else {
                        game.continueAfterRecap()
                    }
                }
                .buttonStyle(ChunkyButtonStyle(height: 64))
                .accessibilityIdentifier("recap.next")
            }
        }
        .onAppear { appeared = true }
    }

    private var headline: String {
        guard let best = game.roundResults.max(by: { $0.value.total < $1.value.total }),
              let player = game.players.first(where: { $0.id == best.key }) else { return "Scores are in" }
        return "\(player.name) nailed it with \(best.value.total)"
    }
}

struct StandingRow: View {
    @Environment(\.uiScale) private var scale
    let rank: Int
    let player: Player
    var roundScore: Int? = nil
    var change: Int = 0

    var body: some View {
        HStack(spacing: 12 * scale) {
            Text("\(rank)")
                .scaledFont(size: 16, weight: .black, design: .rounded)
                .foregroundStyle(rank == 1 ? Theme.ink : .white)
                .frame(width: 30 * scale, height: 30 * scale)
                .background(rank == 1 ? Theme.accent : .white.opacity(0.1), in: Circle())
            PlayerDot(color: player.color, size: 24 * scale)
            Text(player.name)
                .scaledFont(.headline, weight: .bold)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if change != 0 {
                Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .scaledFont(size: 10, weight: .regular, design: .default)
                    .foregroundStyle(change > 0 ? Theme.accent : Theme.danger)
                    .accessibilityLabel(change > 0 ? "up \(change)" : "down \(-change)")
            }
            Spacer()
            if let roundScore {
                Text("+\(roundScore)")
                    .scaledFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.glow)
                    .monospacedDigit()
            }
            Text("\(player.total)")
                .scaledFont(size: 20, weight: .black, design: .rounded)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .frame(minWidth: 44 * scale, alignment: .trailing)
        }
        .padding(.horizontal, 10 * scale)
        .frame(height: 48 * scale)
        .background(rank == 1 ? Theme.panel.opacity(0.72) : .clear, in: RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
