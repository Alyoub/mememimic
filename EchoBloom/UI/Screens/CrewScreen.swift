import SwiftUI

struct CrewScreen: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game
    @FocusState private var focusedName: UUID?
    @State private var listHeight: CGFloat = 0

    var body: some View {
        @Bindable var game = game
        Scaffold {
            HStack {
                IconButton(symbol: "chevron.left", label: "Back") { game.goHome() }
                Spacer()
                VStack(spacing: 2 * scale) {
                    Text("Your crew").scaledFont(size: 22).foregroundStyle(Theme.text)
                    Text("\(game.players.count) of \(GameModel.maxPlayers) players").scaledFont(size: 13, weight: .heavy).foregroundStyle(Theme.muted)
                }
                Spacer()
                Color.clear.frame(width: 46 * scale, height: 46 * scale)
            }
        } bottom: {
            VStack(spacing: 14 * scale) {
                // One scroll view sized to its rows (up to a cap), so the panel hugs a
                // small crew and scrolls a big one. (ViewThatFits swapped between two
                // copies of the list and lost the open editor when it grew.)
                ScrollViewReader { proxy in
                    ScrollView {
                        playerList
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(max(listHeight, 80 * scale), (scale > 1 ? 420 : 330) * scale))
                    .onChange(of: game.editingPlayerID) { _, id in
                        guard let id else { return }
                        withAnimation(.spring(duration: 0.4)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
                .glassPanel()

                RoundsPicker()

                Button("Pick sound packs") {
                    focusedName = nil
                    game.openPacks()
                }
                .buttonStyle(ChunkyButtonStyle())
            }
        }
        .onChange(of: focusedName) { _, id in
            if let id { game.editingPlayerID = id }
            game.commitSetup()
        }
    }

    private var playerList: some View {
        @Bindable var game = game
        return VStack(spacing: 8 * scale) {
            ForEach($game.players) { $player in
                PlayerRow(player: $player,
                          isEditing: game.editingPlayerID == player.id,
                          canRemove: game.players.count > GameModel.minPlayers,
                          focus: $focusedName)
                    .id(player.id)
            }
            if game.players.count < GameModel.maxPlayers {
                Button {
                    game.addPlayer()
                } label: {
                    Label("Add player", systemImage: "plus")
                        .scaledFont(.headline, weight: .bold)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54 * scale)
                        .overlay(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                            .foregroundStyle(Theme.faint))
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .padding(12 * scale)
    }
}

private struct PlayerRow: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game
    @Binding var player: Player
    let isEditing: Bool
    let canRemove: Bool
    var focus: FocusState<UUID?>.Binding

    var body: some View {
        VStack(spacing: 12 * scale) {
            HStack(spacing: 12 * scale) {
                Button {
                    withAnimation(.spring(duration: 0.35)) {
                        game.editingPlayerID = isEditing ? nil : player.id
                    }
                    game.poke(player.id)
                } label: {
                    CharacterBadge(character: player.character, color: player.color, size: 44 * scale)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Change character for \(player.name), currently \(player.character.name)")

                TextField("Name", text: $player.name)
                    .scaledFont(size: 18, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused(focus, equals: player.id)
                    .onChange(of: player.name) { _, name in
                        if name.count > 14 { player.name = String(name.prefix(14)) }
                    }

                if isEditing {
                    Button {
                        focus.wrappedValue = nil
                        game.savePlayer(player.id)
                    } label: {
                        Image(systemName: "checkmark")
                            .scaledFont(size: 14, weight: .black, design: .default)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 34 * scale, height: 34 * scale)
                            .background(Theme.accent, in: Circle())
                            .shadow(color: Theme.accent.opacity(0.5), radius: 8)
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Save \(player.name)")
                    .transition(.scale.combined(with: .opacity))
                }

                if canRemove {
                    Button {
                        game.removePlayer(player.id)
                    } label: {
                        Image(systemName: "xmark")
                            .scaledFont(size: 13, weight: .heavy, design: .default)
                            .foregroundStyle(Theme.muted)
                            .frame(width: 34 * scale, height: 34 * scale)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Remove \(player.name)")
                }
            }
            if isEditing {
                ScrollView(.horizontal) {
                HStack(spacing: 8 * scale) {
                    ForEach(CharacterKind.allCases) { kind in
                        let selected = player.character == kind
                        let unavailable = !game.isCharacterAvailable(kind, for: player.id)
                        Button {
                            game.setCharacter(kind, for: player.id)
                        } label: {
                            VStack(spacing: 4 * scale) {
                                CharacterBadge(character: kind, color: player.color, size: 64 * scale, rounded: 16 * scale * scale)
                                Text(kind.name)
                                    .scaledFont(size: 12, weight: .bold, design: .rounded)
                                    .foregroundStyle(selected ? Theme.text : Theme.muted)
                                    .lineLimit(1)
                            }
                            .padding(6 * scale)
                            .frame(width: 84 * scale)
                            .background(.white.opacity(selected ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2))
                            .overlay(alignment: .topTrailing) {
                                if unavailable {
                                    Image(systemName: "lock.fill")
                                        .scaledFont(size: 10, weight: .black, design: .default)
                                        .foregroundStyle(Theme.cream)
                                        .frame(width: 22 * scale, height: 22 * scale)
                                        .background(Theme.danger, in: Circle())
                                        .offset(x: 3 * scale, y: -3 * scale)
                                }
                            }
                            .opacity(unavailable ? 0.38 : 1)
                            .saturation(unavailable ? 0.25 : 1)
                        }
                        .buttonStyle(PressScaleStyle())
                        .disabled(unavailable)
                        .accessibilityLabel(unavailable ? "\(kind.name), already chosen" : kind.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2 * scale)
                }
                .scrollIndicators(.hidden)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .padding(10 * scale)
        .background(Theme.panel.opacity(isEditing ? 0.78 : 0.48), in: RoundedRectangle(cornerRadius: 20 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous).strokeBorder(isEditing ? Theme.accent.opacity(0.8) : .clear, lineWidth: 1.5))
    }
}

private struct RoundsPicker: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game

    var body: some View {
        HStack(spacing: 10 * scale) {
            Text("Rounds")
                .scaledFont(.headline, weight: .bold)
                .foregroundStyle(Theme.text)
            Spacer()
            ForEach(GameModel.roundOptions, id: \.self) { n in
                let selected = game.roundsTotal == n
                Button {
                    withAnimation(.spring(duration: 0.3)) { game.roundsTotal = n }
                    game.commitSetup()
                    Haptics.select()
                } label: {
                    Text("\(n)")
                        .scaledFont(size: 18, weight: .black, design: .rounded)
                        .foregroundStyle(selected ? Theme.ink : .white)
                        .frame(width: 52 * scale, height: 42 * scale)
                        .background(selected ? Theme.accent : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("\(n) rounds")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 10 * scale)
        .glassPanel(radius: 24)
    }
}

/// A character's portrait framed by the player's identity color.
struct CharacterBadge: View {
    @Environment(\.uiScale) private var scale
    let character: CharacterKind
    let color: BloomColor
    var size: CGFloat = 44
    var rounded: CGFloat? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: rounded ?? size / 2, style: .continuous)
        Image(character.portrait(in: color))
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(color.color.opacity(0.35).gradient)
            .clipShape(shape)
            .overlay(shape.strokeBorder(color.color, lineWidth: 2))
            .accessibilityHidden(true)
    }
}
