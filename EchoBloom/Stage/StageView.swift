import SwiftUI
import RealityKit

/// The persistent 3D stage behind every screen. One scene lives for the whole session;
/// screens only move the camera and the cast.
struct StageView: View {
    @Environment(GameModel.self) private var game
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var director = StageDirector()
    @State private var frameUpdates: EventSubscription?

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            // The SwiftUI theater backdrop supplies the visible red/orange set. Keeping
            // RealityView transparent makes those authored spotlights read consistently.
            content.add(director.root)
            await director.loadCast()
            game.stageDidLoad()
            frameUpdates = content.subscribe(to: SceneEvents.Update.self) { event in
                director.tick(Float(event.deltaTime))
            }
        } update: { _ in
            director.reduceMotion = reduceMotion
            director.sync(stageState)
        } placeholder: {
            Color.clear
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if let id = director.memberID(for: value.entity) {
                        game.poke(id)
                    } else if let kind = director.showcaseKind(for: value.entity) {
                        // Home lineup: tap the middle one to make it react, a side one to pick it.
                        kind == game.hostCharacter ? game.poke() : game.setHostCharacter(kind)
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    // Swipe the home lineup: left brings the next character in.
                    guard game.screen == .home,
                          abs(value.translation.width) > 40,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    game.cycleHostCharacter(value.translation.width < 0 ? 1 : -1)
                }
        )
        .onAppear {
            let game = game
            director.level = { game.micLevelForStage }
        }
        .accessibilityHidden(true)
    }

    private var stageState: StageState {
        var s = StageState()
        s.screen = game.screen
        s.members = game.players.map { .init(id: $0.id, color: $0.color, character: $0.character) }
        switch game.screen {
        case .crew: s.focusID = game.editingPlayerID
        case .handoff, .turn, .reveal: s.focusID = game.currentPlayer.id
        case .home: s.focusID = game.players.first?.id
        default: s.focusID = game.standings.first?.player.id
        }
        s.mood = game.mascotMood
        if game.screen == .reveal, let result = game.lastResult {
            s.audienceMood = result.total >= 62 ? .happy : .idle
        }
        s.ranking = game.standings.map(\.player.id)
        s.beat = game.stageBeat
        s.pokes = game.pokes
        s.pokeID = game.pokeID
        s.homeCharacter = game.hostCharacter
        s.homeColor = game.hostColor
        return s
    }
}
