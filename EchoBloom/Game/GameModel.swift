import SwiftUI
import Observation

enum Screen: Hashable {
    case home, crew, packs, handoff, turn, reveal, recap, podium
}

enum TurnPhase: Equatable {
    case intro, listening, ready, countIn(Int), recording, analyzing

    var isBusy: Bool {
        switch self {
        case .listening, .countIn, .recording, .analyzing: true
        default: false
        }
    }
}

/// The whole match as a state machine:
/// home → crew → packs → [handoff → turn → reveal] × players → recap … → podium.
@MainActor @Observable
final class GameModel {
    static let minPlayers = 1, maxPlayers = 8
    static let roundOptions = [1, 3, 5]
    static let listensPerTurn = 2

    // Navigation
    private(set) var screen: Screen = .home

    // Setup
    var players: [Player] = []
    var roundsTotal = 3
    var packIDs: Set<String> = Set(SoundLibrary.packs.map(\.id))
    var editingPlayerID: UUID?
    private(set) var useRealSounds = true

    // Match
    private(set) var round = 0
    private(set) var turn = 0
    private(set) var roundPrompts: [Prompt] = []
    private(set) var phase: TurnPhase = .intro
    private(set) var listensLeft = listensPerTurn
    private(set) var lastResult: TurnResult?
    private(set) var lastTake: RecordedTake?
    private(set) var roundResults: [UUID: TurnResult] = [:]
    private(set) var ranksBeforeRound: [UUID: Int] = [:]

    // Live audio, sampled ~30× a second while recording
    private(set) var liveLevel = 0.0
    private(set) var levelHistory: [Double] = Array(repeating: 0, count: 40)
    private(set) var recordProgress = 0.0
    private(set) var listenProgress = 0.0

    // Feedback
    private(set) var notice: String?
    private(set) var stageBeat = 0
    private(set) var pokes = 0
    private(set) var pokeID: UUID?
    var showHowToPlay = false

    var muted = false {
        didSet { audio.muted = muted; save() }
    }
    var hapticsOn = true {
        didSet { Haptics.enabled = hapticsOn; save() }
    }
    var showSettings = false

    let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")

    // MARK: Launch

    /// The animated splash covers launch until the 3D stage has loaded. UI tests skip it
    /// unless they pass -show-splash.
    private(set) var isSplashing = !ProcessInfo.processInfo.arguments.contains("-ui-testing")
        || ProcessInfo.processInfo.arguments.contains("-show-splash")
    private(set) var stageReady = false

    func stageDidLoad() { stageReady = true }

    func finishSplash() { isSplashing = false }
    private let audio = AudioEngine()
    private var referenceCache: [String: VoiceAnalyzer.Features] = [:]
    private var turnTask: Task<Void, Never>?
    private var stopRequested = false

    init() {
        load()
        if players.isEmpty {
            players = Self.defaultCrew()
        }
        audio.muted = muted
        Haptics.enabled = hapticsOn
    }

    // MARK: Derived state

    var micDenied: Bool { audio.micAccess == .denied }
    var micAccess: AudioEngine.MicAccess { audio.micAccess }
    var currentPlayerIndex: Int { players.isEmpty ? 0 : (turn + round) % players.count }
    var currentPlayer: Player { players[currentPlayerIndex] }
    var availablePacks: [SoundPack] { SoundLibrary.packs(realSounds: useRealSounds) }
    var currentPrompt: Prompt { roundPrompts.isEmpty ? availablePacks[0].prompts[0] : roundPrompts[round % roundPrompts.count] }
    var isLastTurnOfRound: Bool { turn >= players.count - 1 }
    var isLastRound: Bool { round >= roundsTotal - 1 }
    var nextPlayer: Player? { isLastTurnOfRound ? nil : players[(turn + 1 + round) % players.count] }
    var hostColor: BloomColor { players.first?.color ?? .lime }
    var selectedPacks: [SoundPack] { availablePacks.filter { packIDs.contains($0.id) } }

    /// Players sorted by total score, with tie-aware ranks.
    var standings: [(rank: Int, player: Player)] {
        let sorted = players.sorted { $0.total > $1.total }
        return zip(competitionRanks(sorted.map(\.total)), sorted).map { ($0, $1) }
    }

    var canStartSetup: Bool {
        players.count >= Self.minPlayers
            && players.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            && Set(players.map(\.character)).count == players.count
    }

    /// Where this turn's score sits among the takes so far this round (1-based).
    var roundRankOfLastResult: Int? {
        guard let lastResult else { return nil }
        return roundResults.values.filter { $0.total > lastResult.total }.count + 1
    }

    var mascotMood: MascotMood {
        switch screen {
        case .turn:
            switch phase {
            case .intro: .idle
            case .listening: .listening
            case .ready: .ready
            case .countIn: .countIn
            case .recording: .recording
            case .analyzing: .thinking
            }
        case .reveal: lastResult?.mood ?? .idle
        case .podium: .celebrate
        case .recap: .happy
        default: .idle
        }
    }

    // MARK: Navigation

    func go(_ screen: Screen) {
        withAnimation(.spring(duration: 0.55, bounce: 0.18)) { self.screen = screen }
    }

    func goHome() {
        cancelTurn()
        isConfirmingQuit = false
        go(.home)
    }

    // MARK: Quitting a match

    private(set) var isConfirmingQuit = false

    func askToQuit() {
        Haptics.tap()
        withAnimation(.spring(duration: 0.3)) { isConfirmingQuit = true }
    }

    func keepPlaying() {
        withAnimation(.spring(duration: 0.3)) { isConfirmingQuit = false }
    }

    func confirmQuit() {
        Haptics.thump()
        goHome()
    }

    func openCrew() {
        Haptics.tap()
        go(.crew)
    }

    func openPacks() {
        guard canStartSetup else {
            flash("Every player needs a name.")
            Haptics.warning()
            return
        }
        players = players.map { var p = $0; p.name = p.name.trimmingCharacters(in: .whitespaces); return p }
        editingPlayerID = nil
        save()
        Haptics.tap()
        go(.packs)
    }

    /// Swaps third-party meme clips for original synthesized prompts when remote config
    /// disables `realSound`. Pack IDs stay stable, so saved selections still work.
    func setRealSounds(_ enabled: Bool) {
        guard useRealSounds != enabled else { return }
        useRealSounds = enabled
        roundPrompts = []
        referenceCache = [:]
        let validIDs = Set(availablePacks.map(\.id))
        packIDs.formIntersection(validIDs)
        if packIDs.isEmpty { packIDs = validIDs }
    }

    // MARK: Crew editing

    func addPlayer() {
        guard players.count < Self.maxPlayers else { return }
        let color = Self.randomColor(avoiding: Set(players.map(\.color)))
        let usedCharacters = Set(players.map(\.character))
        guard let character = CharacterKind.allCases.first(where: { !usedCharacters.contains($0) }) else { return }
        let player = Player(name: "Player \(players.count + 1)", color: color, character: character)
        withAnimation(.spring(duration: 0.4)) { players.append(player) }
        editingPlayerID = player.id
        Haptics.tap()
    }

    /// A random color no current player has, so every player stays distinct.
    private static func randomColor(avoiding used: Set<BloomColor>) -> BloomColor {
        BloomColor.allCases.filter { !used.contains($0) }.randomElement() ?? BloomColor.allCases.randomElement()!
    }

    private static func defaultCrew() -> [Player] {
        let first = randomColor(avoiding: [])
        return [Player(name: "Player 1", color: first, character: .pirateGal)]
    }

    /// Older saves allowed duplicate characters. Keep every player and deterministically
    /// move only duplicates to the first unused character.
    private static func assigningUniqueCharacters(to crew: [Player]) -> [Player] {
        var used: Set<CharacterKind> = []
        return crew.map { player in
            var player = player
            if used.contains(player.character),
               let replacement = CharacterKind.allCases.first(where: { !used.contains($0) }) {
                player.character = replacement
            }
            used.insert(player.character)
            return player
        }
    }

    /// The ✓ on an open player row: tidies the name, saves, and closes the editor.
    func savePlayer(_ id: UUID) {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return }
        let name = players[i].name.trimmingCharacters(in: .whitespaces)
        players[i].name = name.isEmpty ? "Player \(i + 1)" : name
        save()
        withAnimation(.spring(duration: 0.35)) { editingPlayerID = nil }
        poke(id)
        Haptics.success()
    }

    /// Settings → Reset crew: back to one player with a fresh color and default options.
    func resetCrew() {
        withAnimation(.spring(duration: 0.4)) { players = Self.defaultCrew() }
        editingPlayerID = nil
        roundsTotal = 3
        packIDs = Set(availablePacks.map(\.id))
        save()
        Haptics.success()
    }

    func removePlayer(_ id: UUID) {
        guard players.count > Self.minPlayers else { return }
        withAnimation(.spring(duration: 0.4)) { players.removeAll { $0.id == id } }
        if editingPlayerID == id { editingPlayerID = nil }
        Haptics.tap()
    }

    /// The host (player 1) picks their character from the home screen lineup.
    var hostCharacter: CharacterKind { players.first?.character ?? .pirateGal }

    func cycleHostCharacter(_ step: Int) {
        let kinds = CharacterKind.allCases
        guard let host = players.first, let i = kinds.firstIndex(of: hostCharacter) else { return }
        let direction = step >= 0 ? 1 : -1
        for distance in 1...kinds.count {
            let candidate = kinds[(i + direction * distance + kinds.count) % kinds.count]
            if isCharacterAvailable(candidate, for: host.id) {
                setHostCharacter(candidate)
                return
            }
        }
    }

    func setHostCharacter(_ character: CharacterKind) {
        guard let host = players.first else { return }
        setCharacter(character, for: host.id)
    }

    func isCharacterAvailable(_ character: CharacterKind, for id: UUID) -> Bool {
        !players.contains { $0.id != id && $0.character == character }
    }

    /// Each crew member must have a different character.
    func setCharacter(_ character: CharacterKind, for id: UUID) {
        guard let i = players.firstIndex(where: { $0.id == id }), players[i].character != character else { return }
        guard isCharacterAvailable(character, for: id) else {
            flash("\(character.name) is already taken.")
            Haptics.warning()
            return
        }
        players[i].character = character
        commitSetup()
        audio.cue(.pop)
        Haptics.select()
    }

    func togglePack(_ id: String) {
        if packIDs.contains(id) {
            guard packIDs.count > 1 else { flash("Keep at least one pack."); Haptics.warning(); return }
            packIDs.remove(id)
        } else {
            packIDs.insert(id)
        }
        Haptics.select()
        save()
    }

    func preview(_ pack: SoundPack) {
        guard let prompt = pack.prompts.first else { return }
        audio.play(SoundLibrary.render(prompt), force: true)
    }

    /// Makes a mascot hop and spin; nil pokes whoever has the spotlight.
    func poke(_ id: UUID? = nil) {
        pokeID = id
        pokes += 1
        audio.cue(.pop)
        Haptics.tap()
    }

    // MARK: Match flow

    func startMatch() {
        cancelTurn()
        for i in players.indices { players[i].roundScores = [] }
        let pool = selectedPacks.flatMap(\.prompts).shuffled()
        roundPrompts = (0..<roundsTotal).map { pool[$0 % pool.count] }
        round = 0
        turn = 0
        beginRound()
        save()
        Haptics.success()
    }

    private func beginRound() {
        roundResults = [:]
        ranksBeforeRound = Dictionary(uniqueKeysWithValues: standings.map { ($0.player.id, $0.rank) })
        resetTurn()
        go(.handoff)
    }

    func takeThePhone() {
        Haptics.tap()
        resetTurn()
        go(.turn)
    }

    func listen() {
        guard listensLeft > 0, !phase.isBusy else { return }
        listensLeft -= 1
        let samples = SoundLibrary.render(currentPrompt)
        let seconds = audio.play(samples, force: true)
        phase = .listening
        listenProgress = 0
        Haptics.tap()
        turnTask = Task { [weak self] in
            let start = Date()
            while let self, !Task.isCancelled {
                let t = Date().timeIntervalSince(start) / seconds
                self.listenProgress = min(1, t)
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            guard let self, !Task.isCancelled else { return }
            self.phase = .ready
        }
    }

    func startTake() {
        guard phase == .ready else { return }
        turnTask = Task { [weak self] in await self?.runTake() }
    }

    func stopTake() {
        guard phase == .recording else { return }
        stopRequested = true
        Haptics.tap()
    }

    private func runTake() async {
        guard await audio.requestMic() else {
            flash("Microphone is off. Use the demo take, or allow it in Settings.")
            Haptics.warning()
            return
        }
        for n in [3, 2, 1] {
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { phase = .countIn(n) }
            stageBeat += 1
            audio.cue(.tick)
            Haptics.tick()
            try? await Task.sleep(for: .milliseconds(isUITesting ? 50 : 700))
            if Task.isCancelled { return }
        }
        guard await audio.startRecording(), !Task.isCancelled else {
            phase = .ready
            flash("Couldn't open the microphone. Try the demo take.")
            return
        }
        Haptics.thump()
        phase = .recording
        stopRequested = false
        recordProgress = 0

        let maxDuration = max(2.5, currentPrompt.duration + 1.6)
        let start = Date()
        var heardVoice = false
        var quietSince: Date?
        while !Task.isCancelled, !stopRequested {
            let elapsed = Date().timeIntervalSince(start)
            let level = Double(audio.inputLevel)
            let shown = min(1, pow(level * 9, 0.6))
            liveLevel += (shown - liveLevel) * 0.5
            levelHistory.removeFirst()
            levelHistory.append(liveLevel)
            recordProgress = min(1, elapsed / maxDuration)

            // Stop on our own once the player clearly finished.
            if level > 0.03 { heardVoice = true; quietSince = nil }
            else if heardVoice, level < 0.012 { quietSince = quietSince ?? Date() }
            if let quietSince, Date().timeIntervalSince(quietSince) > 0.9, elapsed > currentPrompt.duration * 0.6 { break }
            if elapsed >= maxDuration { break }
            try? await Task.sleep(for: .milliseconds(33))
        }
        let take = await audio.stopRecording()
        liveLevel = 0
        if Task.isCancelled { return }
        phase = .analyzing
        await analyze(take)
    }

    private func analyze(_ take: RecordedTake?) async {
        let prompt = currentPrompt
        let cached = referenceCache[prompt.id]
        let analysis = await Task.detached(priority: .userInitiated) { () -> (VoiceAnalyzer.Features?, VoiceAnalyzer.Features?) in
            let reference = cached ?? VoiceAnalyzer.features(SoundLibrary.render(prompt), sampleRate: SoundLibrary.sampleRate)
            let features = take.flatMap { VoiceAnalyzer.features($0.samples, sampleRate: $0.sampleRate) }
            return (reference, features)
        }.value
        // Give the "thinking" beat a moment to read, even when analysis is instant.
        try? await Task.sleep(for: .milliseconds(isUITesting ? 50 : 900))
        guard !Task.isCancelled, phase == .analyzing else { return }
        referenceCache[prompt.id] = analysis.0

        guard let reference = analysis.0, let features = analysis.1 else {
            phase = .ready
            levelHistory = Array(repeating: 0, count: levelHistory.count)
            flash("Didn't catch that. Get closer and go again!")
            Haptics.warning()
            return
        }
        lastTake = take
        finishTurn(with: VoiceAnalyzer.score(take: features, reference: reference))
    }

    /// A clearly labeled, deterministic score so the game works without a microphone.
    func useDemoTake() {
        cancelTurn()
        let seed = (currentPrompt.id + currentPlayer.name + "\(round)").unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let total = 40 + seed % 55
        lastTake = nil
        finishTurn(with: TurnResult(total: total, pitch: 35 + seed % 60, rhythm: 40 + (seed / 7) % 55, length: 50 + (seed / 13) % 50, isDemo: true))
    }

    private func finishTurn(with result: TurnResult) {
        lastResult = result
        roundResults[currentPlayer.id] = result
        players[currentPlayerIndex].roundScores.append(result.total)
        audio.cue(.reveal)
        go(.reveal)
    }

    func replayTake() {
        guard let lastTake else { return }
        audio.playTake(lastTake)
    }

    func replayPrompt() {
        audio.play(SoundLibrary.render(currentPrompt), force: true)
    }

    func continueAfterReveal() {
        Haptics.tap()
        audio.stopPlayback()
        if isLastTurnOfRound {
            go(.recap)
        } else {
            turn += 1
            resetTurn()
            go(.handoff)
        }
    }

    func continueAfterRecap() {
        Haptics.tap()
        if isLastRound {
            Haptics.success()
            go(.podium)
        } else {
            round += 1
            turn = 0
            beginRound()
        }
    }

    func rankChange(for player: Player, now: Int) -> Int {
        guard let before = ranksBeforeRound[player.id], round > 0 else { return 0 }
        return before - now
    }

    // MARK: Helpers

    private func resetTurn() {
        cancelTurn()
        phase = .intro
        listensLeft = Self.listensPerTurn
        lastResult = nil
        lastTake = nil
        listenProgress = 0
        recordProgress = 0
        levelHistory = Array(repeating: 0, count: levelHistory.count)
    }

    private func cancelTurn() {
        turnTask?.cancel()
        turnTask = nil
        audio.cancelRecording()
        audio.stopPlayback()
        liveLevel = 0
        if phase.isBusy { phase = .ready }
    }

    func flash(_ text: String) {
        withAnimation(.spring(duration: 0.35)) { notice = text }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard let self, self.notice == text else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.notice = nil }
        }
    }

    // MARK: Persistence

    private struct Saved: Codable {
        var players: [Player]
        var rounds: Int
        var packs: [String]
        var muted: Bool
        var haptics: Bool?   // optional: older saves don't have it
    }

    private func save() {
        guard !isUITesting else { return }
        let saved = Saved(players: players, rounds: roundsTotal, packs: Array(packIDs), muted: muted, haptics: hapticsOn)
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "echobloom.setup.v2") }
    }

    private func load() {
        guard !isUITesting,
              let data = UserDefaults.standard.data(forKey: "echobloom.setup.v2"),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        players = Self.assigningUniqueCharacters(to: Array(saved.players.prefix(Self.maxPlayers)))
        roundsTotal = Self.roundOptions.contains(saved.rounds) ? saved.rounds : 3
        let valid = Set(saved.packs).intersection(SoundLibrary.packs.map(\.id))
        if !valid.isEmpty { packIDs = valid }
        muted = saved.muted
        hapticsOn = saved.haptics ?? true
    }

    /// Persist after edits made directly through bindings (names, rounds).
    func commitSetup() { save() }

    var micLevelForStage: Double { phase == .recording ? liveLevel : 0 }
}
