import StoreKit
import SwiftUI

struct PodiumScreen: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game
    @Environment(\.requestReview) private var requestReview
    @AppStorage("memeMimic.didRequestReviewAfterFirstMatch") private var didRequestReview = false

    var body: some View {
        let standings = game.standings
        let winners = standings.filter { $0.rank == 1 }.map(\.player)
        Scaffold {
            VStack(spacing: 8 * scale) {
                Eyebrow(text: "Final results", color: Theme.accent)
                    .accessibilityIdentifier("final.label")
                Text(winners.count > 1 ? "It's a tie!" : "\(winners.first?.name ?? "Someone") wins!")
                    .scaledFont(size: 40)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .shadow(color: Theme.glow.opacity(0.65), radius: 24)
            }
            .padding(.top, 8 * scale)
        } bottom: {
            VStack(spacing: 12 * scale) {
                ScrollView {
                    VStack(spacing: 4 * scale) {
                        ForEach(standings, id: \.player.id) { entry in
                            StandingRow(rank: entry.rank, player: entry.player)
                        }
                    }
                    .padding(10 * scale)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 230 * scale)
                .glassPanel()

                Button("Rematch") { game.startMatch() }
                    .buttonStyle(ChunkyButtonStyle(height: 64))
                HStack(spacing: 10 * scale) {
                    Button("Change crew") { game.go(.crew) }
                        .buttonStyle(GlassButtonStyle())
                    Button("Home") { game.goHome() }
                        .buttonStyle(GlassButtonStyle())
                }
            }
        }
        .task {
            guard !didRequestReview,
                  !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }

            // Let the winner screen settle after the preceding full-screen ad before
            // asking for a rating. Leaving the podium cancels this task automatically.
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, game.screen == .podium else { return }
            didRequestReview = true
            requestReview()
        }
    }
}
