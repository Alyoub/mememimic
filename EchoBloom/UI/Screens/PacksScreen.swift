import SwiftUI

struct PacksScreen: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game
    @State private var listHeight: CGFloat = 0

    var body: some View {
        Scaffold {
            HStack {
                IconButton(symbol: "chevron.left", label: "Back") { game.go(.crew) }
                Spacer()
                VStack(spacing: 2 * scale) {
                    Text("Sound packs").scaledFont(size: 22).foregroundStyle(Theme.text)
                    Text("\(game.selectedPacks.reduce(0) { $0 + $1.prompts.count }) sounds in the mix").scaledFont(size: 13, weight: .heavy).foregroundStyle(Theme.muted)
                }
                Spacer()
                MuteButton()
            }
        } bottom: {
            VStack(spacing: 14 * scale) {
                // Compact rows that scroll once there are more packs than fit, so the
                // stage above always keeps its space.
                ScrollView {
                    VStack(spacing: 10 * scale) {
                        ForEach(game.availablePacks) { pack in
                            PackCard(pack: pack, selected: game.packIDs.contains(pack.id))
                        }
                    }
                    .padding(.vertical, 4 * scale)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                // iPad has room for every pack without scrolling.
                .frame(height: min(max(listHeight, 70 * scale), (scale > 1 ? 470 : 380) * scale))
                Button("Start the match") { game.startMatch() }
                    .buttonStyle(ChunkyButtonStyle(height: 66))
            }
        }
    }
}

/// One pack as a colorful "ticket": its own tint drives the icon tile, the side glow,
/// the outline and the check, so the list reads as five distinct packs instead of five
/// identical gold rows.
private struct PackCard: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game
    let pack: SoundPack
    let selected: Bool
    @State private var playing = false
    @State private var playToken = 0

    private var tint: Color { pack.tint.color }

    var body: some View {
        HStack(spacing: 14 * scale) {
            iconTile

            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(pack.name)
                    .scaledFont(size: 18, weight: .heavy, design: .rounded)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(pack.blurb)
                    .scaledFont(.footnote, weight: .medium)
                    .foregroundStyle(selected ? Theme.muted : Theme.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)

            previewButton
            checkmark
        }
        .padding(.leading, 10 * scale)
        .padding(.trailing, 12 * scale)
        .padding(.vertical, 10 * scale)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                .strokeBorder(
                    selected
                        ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.10)),
                    lineWidth: selected ? 2 : 1
                )
        )
        .shadow(color: tint.opacity(selected ? 0.30 : 0), radius: 12, y: 4)
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(duration: 0.35, bounce: 0.45)) { game.togglePack(pack.id) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(pack.name)
        .accessibilityValue("\(pack.prompts.count) sounds")
        .accessibilityHint(pack.blurb)
        .accessibilityAction { game.togglePack(pack.id) }
    }

    /// Tinted, slightly tilted tile with a sound-count badge tucked in the corner.
    private var iconTile: some View {
        Image(systemName: pack.symbol)
            .scaledFont(size: 22, weight: .bold, design: .default)
            .foregroundStyle(Theme.ink)
            .frame(width: 52 * scale, height: 52 * scale)
            .background {
                RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                    .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.25), tint, tint.mix(with: .black, by: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                            .padding(2 * scale)
                    }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 2 * scale) {
                    Image(systemName: "waveform").scaledFont(size: 8, weight: .black, design: .default)
                    Text("\(pack.prompts.count)").scaledFont(size: 11, weight: .black, design: .rounded)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 6 * scale)
                .frame(height: 19 * scale)
                .background(Theme.ink, in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.7), lineWidth: 1.2))
                .offset(x: 7 * scale, y: 6 * scale)
            }
            .rotationEffect(.degrees(selected ? -5 : 0))
            .scaleEffect(selected ? 1 : 0.92)
            .saturation(selected ? 1 : 0.25)
            .opacity(selected ? 1 : 0.7)
            .shadow(color: tint.opacity(selected ? 0.55 : 0), radius: 8, y: 3)
            .padding(.trailing, 4 * scale)
    }

    private var previewButton: some View {
        Button {
            game.preview(pack)
            playToken += 1
            let token = playToken
            let seconds = min(max(pack.prompts.first?.duration ?? 1.5, 0.8), 6)
            withAnimation(.spring(duration: 0.25)) { playing = true }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if token == playToken { withAnimation(.spring(duration: 0.25)) { playing = false } }
            }
        } label: {
            Image(systemName: playing ? "waveform" : "play.fill")
                .scaledFont(size: playing ? 15 : 13, weight: .black, design: .default)
                .foregroundStyle(playing ? Theme.ink : Theme.text)
                .symbolEffect(.variableColor.iterative.reversing, isActive: playing)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38 * scale, height: 38 * scale)
                .background(playing ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.16)), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(playing ? 0 : 0.45), lineWidth: 1.2))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Preview \(pack.name)")
    }

    private var checkmark: some View {
        ZStack {
            Circle()
                .fill(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.clear))
            Circle()
                .strokeBorder(selected ? .white.opacity(0.35) : Theme.faint, style: StrokeStyle(lineWidth: 2, dash: selected ? [] : [4, 3]))
            Image(systemName: selected ? "checkmark" : "plus")
                .scaledFont(size: 13, weight: .black, design: .default)
                .foregroundStyle(selected ? Theme.ink : Theme.faint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 30 * scale, height: 30 * scale)
        .scaleEffect(selected ? 1 : 0.9)
        .symbolEffect(.bounce, value: selected)
    }

    /// Glass card with the pack's color washing in from the left edge.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 22 * scale, style: .continuous).fill(Theme.panel.opacity(selected ? 0.55 : 0.72)))
            .overlay(
                RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                    .fill(RadialGradient(colors: [tint.opacity(selected ? 0.38 : 0.06), .clear], center: UnitPoint(x: 0.08, y: 0.5), startRadius: 0, endRadius: 190 * scale))
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(selected ? 0.10 : 0.04), .clear], startPoint: .top, endPoint: .center))
            }
    }
}
