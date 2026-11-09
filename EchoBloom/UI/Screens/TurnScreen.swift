import SwiftUI

struct TurnScreen: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        let player = game.currentPlayer
        Scaffold {
            VStack(spacing: 12 * scale) {
                MatchTopBar()
                PlayerChip(player: player)
            }
        } bottom: {
            VStack(spacing: 18 * scale) {
                PromptCard()
                Controls()
            }
        }
        .overlay { CountInOverlay() }
    }
}

private struct PromptCard: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        let accent = Theme.accent
        VStack(spacing: 14 * scale) {
            VStack(spacing: 6 * scale) {
                Eyebrow(text: status, color: accent)
                    .contentTransition(.opacity)
                Text(game.currentPrompt.name)
                    .scaledFont(size: 32)
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(game.currentPrompt.hint)
                    .scaledFont(.body, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if game.phase == .recording || game.phase == .analyzing {
                    WaveBars(values: game.levelHistory, color: accent, minHeight: 4)
                        .accessibilityLabel("Your voice level")
                } else {
                    WaveBars(values: SoundLibrary.envelope(game.currentPrompt, bars: 40),
                             color: accent,
                             progress: game.phase == .listening ? game.listenProgress : (game.listensLeft < GameModel.listensPerTurn ? 1 : 0))
                        .accessibilityLabel("Sound shape")
                }
            }
            .frame(height: 54 * scale)
            .padding(.horizontal, 4 * scale)
            .animation(.easeInOut(duration: 0.25), value: game.phase == .recording)
        }
        .padding(20 * scale)
        .glassPanel()
    }

    private var status: String {
        switch game.phase {
        case .intro: "Your sound"
        case .listening: "Listen closely…"
        case .ready: "Your turn to copy it"
        case .countIn: "Get ready"
        case .recording: "Recording, go!"
        case .analyzing: "Judging your echo…"
        }
    }
}

private struct Controls: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        let accent = Theme.accent
        VStack(spacing: 12 * scale) {
            switch game.phase {
            case .intro, .listening:
                Button {
                    game.listen()
                } label: {
                    Label(game.phase == .listening ? "Playing…" : "Play the sound", systemImage: "speaker.wave.3.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: accent, height: 66))
                .disabled(game.phase == .listening)

                Button {
                    game.useDemoTake()
                } label: {
                    Label("No mic? Use a demo take", systemImage: "wand.and.stars")
                        .scaledFont(.footnote, weight: .bold)
                        .foregroundStyle(Theme.muted)
                        .frame(minHeight: 32 * scale)
                }
                .buttonStyle(PressScaleStyle())
                .disabled(game.phase.isBusy)
                .accessibilityLabel("Demo take")

            case .ready, .countIn, .recording, .analyzing:
                HStack(alignment: .center, spacing: 20 * scale) {
                    SideAction(symbol: "arrow.counterclockwise", title: "Hear again", detail: "\(game.listensLeft) left") {
                        game.listen()
                    }
                    .disabled(game.listensLeft == 0 || game.phase != .ready)

                    RecordButton()

                    SideAction(symbol: "wand.and.stars", title: "Demo take", detail: "no mic") {
                        game.useDemoTake()
                    }
                    .disabled(game.phase.isBusy)
                }
            }
            if game.micDenied {
                Text("Microphone is off for Meme Mimic. Turn it on in Settings, or play with demo takes.")
                    .scaledFont(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.spring(duration: 0.4), value: game.phase)
    }
}

private struct SideAction: View {
    @Environment(\.uiScale) private var scale
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6 * scale) {
                Image(systemName: symbol)
                    .scaledFont(size: 18, weight: .bold, design: .default)
                    .frame(width: 52 * scale, height: 52 * scale)
                    .background(.white.opacity(0.1), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke))
                VStack(spacing: 0 * scale) {
                    Text(title).scaledFont(size: 12, weight: .bold, design: .rounded)
                    Text(detail).scaledFont(size: 11, weight: .medium, design: .rounded).foregroundStyle(Theme.faint)
                }
            }
            .foregroundStyle(Theme.text)
            .opacity(isEnabled ? 1 : 0.35)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }
}

/// The hero control: record, then stop. Its ring shows take progress and pulses with the voice.
private struct RecordButton: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        let accent = Theme.accent
        let recording = game.phase == .recording
        let busy = game.phase.isBusy && !recording
        Button {
            recording ? game.stopTake() : game.startTake()
        } label: {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.25))
                    .scaleEffect(1 + game.liveLevel * 0.35)
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 6)
                    .padding(6 * scale)
                Circle()
                    .trim(from: 0, to: recording ? game.recordProgress : 0)
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(6 * scale)
                Circle()
                    .fill(recording ? Theme.danger : accent)
                    .padding(16 * scale)
                    .shadow(color: (recording ? Theme.danger : accent).opacity(0.6), radius: 16)
                Group {
                    if game.phase == .analyzing {
                        ProgressView().tint(Theme.ink).controlSize(.large)
                    } else {
                        Image(systemName: recording ? "stop.fill" : "mic.fill")
                            .scaledFont(size: 30, weight: .black, design: .default)
                            .foregroundStyle(recording ? .white : Theme.ink)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .frame(width: 112 * scale, height: 112 * scale)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(busy)
        .accessibilityLabel(recording ? "Stop recording" : "Record your take")
        .accessibilityIdentifier("record")
    }
}

private struct CountInOverlay: View {
    @Environment(\.uiScale) private var scale
    @Environment(\.sidePanelWidth) private var sidePanelWidth
    @Environment(GameModel.self) private var game

    var body: some View {
        if case .countIn(let n) = game.phase {
            Text("\(n)")
                .scaledFont(size: 150)
                .foregroundStyle(Theme.text)
                .shadow(color: Theme.glow, radius: 30)
                .id(n)
                .transition(.asymmetric(insertion: .scale(scale: 1.8).combined(with: .opacity), removal: .scale(scale: 0.6).combined(with: .opacity)))
                .allowsHitTesting(false)
                // Over the stage, which sits left of the controls on a wide iPad.
                .offset(x: -(sidePanelWidth ?? 0) / 2, y: -140 * scale)
                .accessibilityLabel("Starting in \(n)")
        }
    }
}
