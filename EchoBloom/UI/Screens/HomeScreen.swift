import SwiftUI

struct HomeScreen: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        Scaffold {
            HStack {
                Wordmark()
                Spacer()
                HStack(spacing: 8 * scale) {
                    MuteButton()
                    SettingsButton()
                }
            }
        } bottom: {
            VStack(spacing: 15 * scale) {
                CharacterSelector()
                VStack(spacing: 10 * scale) {
                    VStack(spacing: -2 * scale) {
                        Text("Copy the sound.")
                            .foregroundStyle(Theme.text)
                            .shadow(color: Theme.ink.opacity(0.85), radius: 0, y: 5)
                        HStack(spacing: 8 * scale) {
                            BurstMarks()
                            Text("Win the room.")
                                .foregroundStyle(Theme.accent)
                                .shadow(color: Theme.accentDepth.opacity(0.95), radius: 0, y: 5)
                            BurstMarks(mirrored: true)
                        }
                    }
                    .scaledFont(size: 37)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    Text("A party game for 1–8 players.")
                        .scaledFont(size: 16, weight: .semibold, design: .rounded)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 10 * scale) {
                    Button { game.openCrew() } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(height: 68))
                    Button { game.showHowToPlay = true } label: {
                        Label("How to play", systemImage: "book")
                    }
                    .buttonStyle(GlassButtonStyle(height: 56, stroke: Theme.danger.opacity(0.72)))
                }
            }
        }
    }
}

private struct BurstMarks: View {
    @Environment(\.uiScale) private var scale
    var mirrored = false

    var body: some View {
        ZStack {
            Capsule().frame(width: 19 * scale, height: 4 * scale).rotationEffect(.degrees(-38)).offset(y: -11 * scale)
            Capsule().frame(width: 16 * scale, height: 4 * scale)
            Capsule().frame(width: 19 * scale, height: 4 * scale).rotationEffect(.degrees(38)).offset(y: 11 * scale)
        }
        .foregroundStyle(Theme.glow)
        .frame(width: 24 * scale, height: 38 * scale)
        .scaleEffect(x: mirrored ? -1 : 1)
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    @Environment(\.uiScale) private var scale
    var body: some View {
        HStack(spacing: 10 * scale) {
            HStack(spacing: -6 * scale) {
                Circle().fill(Theme.accent).frame(width: 18 * scale, height: 18 * scale)
                Circle().fill(Theme.cream).frame(width: 22 * scale, height: 22 * scale)
                Circle().fill(Theme.danger).frame(width: 18 * scale, height: 18 * scale)
            }
            Text("MEME MIMIC")
                .scaledFont(size: 18, weight: .black, design: .rounded)
                .tracking(1.5)
                .foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meme Mimic")
    }
}

struct MuteButton: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        IconButton(symbol: game.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                   label: game.muted ? "Turn sound effects on" : "Turn sound effects off") {
            game.muted.toggle()
            Haptics.select()
        }
    }
}

struct SettingsButton: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game
    @EnvironmentObject private var ads: AdsManager

    var body: some View {
        IconButton(symbol: "gearshape.fill", label: "Settings") {
            ads.showRewarded { _ in
                game.showSettings = true
                Haptics.select()
            }
        }
    }
}

struct HowToPlaySheet: View {
    @Environment(\.uiScale) private var scale
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String, String)] = [
        ("ear.fill", "Listen", "Everyone gets the same weird sound each round. You can hear it twice."),
        ("mic.fill", "Imitate", "Hold the phone close and copy it. The pitch, the rhythm, the length all count."),
        ("trophy.fill", "Score & pass", "Your Bloom judges the echo out of 100, then the phone moves on."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24 * scale) {
            HStack {
                Text("How to play")
                    .scaledFont(size: 32)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .scaledFont(size: 17, weight: .bold, design: .default)
                        .frame(width: 42 * scale, height: 42 * scale)
                        .background(Theme.panel, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.accent.opacity(0.55)))
                }
                .accessibilityLabel("Close")
            }
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 16 * scale) {
                    Image(systemName: steps[i].0)
                        .scaledFont(size: 22, weight: .bold, design: .default)
                        .foregroundStyle(Theme.ink)
                        .frame(width: 52 * scale, height: 52 * scale)
                        .background([Theme.accent, Theme.glow, Theme.danger][i], in: RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
                    VStack(alignment: .leading, spacing: 4 * scale) {
                        Text(steps[i].1).scaledFont(.headline, weight: .bold)
                        Text(steps[i].2).scaledFont(.body, weight: .medium).foregroundStyle(Theme.muted)
                    }
                }
            }
            Text("Everything stays on this phone. Recordings are scored on-device and never uploaded.")
                .scaledFont(.footnote)
                .foregroundStyle(Theme.faint)
            Spacer(minLength: 0)
            Button("Got it") { dismiss() }
                .buttonStyle(ChunkyButtonStyle())
        }
        .padding(24 * scale)
        .padding(.top, 12 * scale)
        .foregroundStyle(Theme.text)
        // The half-height detent clips this sheet in iPad's form-sized card.
        .presentationDetents(scale > 1 ? [.large] : [.medium, .large])
        .presentationBackground(Theme.ink)
        .presentationCornerRadius(36)
    }
}

/// Picks the host's character: arrows either side of the name, dots for position. The
/// 3D lineup above also responds to swipes and taps.
private struct CharacterSelector: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        let kinds = CharacterKind.allCases
        let current = game.hostCharacter
        VStack(spacing: 8 * scale) {
            HStack(spacing: 14 * scale) {
                arrow("chevron.left", label: "Previous character") { game.cycleHostCharacter(-1) }
                VStack(spacing: 2 * scale) {
                    Eyebrow(text: "Swipe to choose", color: Theme.muted)
                    Text(current.name)
                        .scaledFont(size: 26)
                        .foregroundStyle(Theme.text)
                        .contentTransition(.opacity)
                        .accessibilityIdentifier("home.character")
                }
                .frame(maxWidth: .infinity)
                arrow("chevron.right", label: "Next character") { game.cycleHostCharacter(1) }
            }
            HStack(spacing: 6 * scale) {
                ForEach(kinds) { kind in
                    Capsule()
                        .fill(kind == current ? Theme.accent : .white.opacity(0.28))
                        .frame(width: kind == current ? 18 * scale : 6 * scale, height: 6 * scale)
                }
            }
            .accessibilityHidden(true)
        }
        .animation(.spring(duration: 0.35), value: current)
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(size: 18, weight: .heavy, design: .default)
                .foregroundStyle(Theme.text)
                .frame(width: 54 * scale, height: 54 * scale)
                .background(Theme.panel.opacity(0.72), in: Circle())
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.62), lineWidth: 1.5))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}
