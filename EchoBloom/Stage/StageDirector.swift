import RealityKit
import UIKit
import simd

/// What the 3D stage needs to know about the game. Rebuilt from `GameModel` on change.
struct StageState: Equatable {
    struct Member: Equatable { let id: UUID; let color: BloomColor; let character: CharacterKind }

    var screen: Screen = .home
    var members: [Member] = []
    var focusID: UUID?
    var mood: MascotMood = .idle
    var audienceMood: MascotMood = .idle
    /// Player ids best-first, for recap and podium layouts.
    var ranking: [UUID] = []
    var beat = 0
    var pokes = 0
    var pokeID: UUID?
    /// The host's character and color, shown center stage in the home screen lineup.
    var homeCharacter: CharacterKind = .pirateGal
    var homeColor: BloomColor = .lime
}

/// Owns the RealityKit scene: stage, lights, camera, effects and one rig per player.
@MainActor
final class StageDirector {
    let root = Entity()
    private let camera = PerspectiveCamera()
    private let ibl = Entity()
    private let ring: ModelEntity
    private let stageTop: ModelEntity
    private var shockwaves: [(entity: ModelEntity, age: Float)] = []
    private let podium = Entity()
    private var podiumBlocks: [ModelEntity] = []
    private var podiumRise = Spring(0, stiffness: 60, damping: 11)
    private let confetti = Entity()
    private var rigs: [UUID: MascotRig] = [:]
    /// One of every character for the home screen lineup, separate from the players.
    private var showcase: [CharacterKind: MascotRig] = [:]
    private var state = StageState()
    private var time: Double = 0
    private var cameraPosition = SIMD3<Float>(0, 1.1, 4)
    private var cameraTarget = SIMD3<Float>(0, 0.3, 0)
    /// Ring and shockwave color: marquee gold, or the active player's color during their turn.
    private var accent: UIColor = StageDirector.glow
    static let glow = UIColor(red: 1, green: 0.80, blue: 0.20, alpha: 1)      // marquee gold
    static let rose = UIColor(red: 1, green: 0.16, blue: 0.08, alpha: 1)     // hot red-orange
    static let gold = UIColor(red: 1, green: 0.70, blue: 0.12, alpha: 1)
    static let cream = UIColor(red: 1, green: 0.965, blue: 0.89, alpha: 1)
    private var lastLevelPeak: Double = 0

    /// Live microphone level, read every frame while recording.
    var level: () -> Double = { 0 }
    var reduceMotion = false
    /// The night-sky backdrop behind the stage.
    private(set) var skybox: EnvironmentResource?
    /// One loaded model per character; every player's rig is a clone. Loaded by `loadCast()`.
    private var templates: [CharacterKind: Entity] = [:]

    func loadCast() async {
        for kind in CharacterKind.allCases {
            templates[kind] = try? await Entity(named: kind.asset, in: .main)
        }
        let current = state
        state = StageState()
        sync(current)
    }

    init() {
        // Glowing scarlet stage from the reference, with enough value in the horizon to
        // keep black-faced characters and dark outfits clearly readable.
        if let image = Self.gradientImage(top: StageColors.skyTop, horizon: StageColors.skyHorizon, bottom: StageColors.skyBottom) {
            skybox = try? EnvironmentResource(equirectangular: image, withName: "night")
        }

        // Lighting: a soft studio environment plus key, rim and fill lights.
        // Neutral studio light preserves outfit colors while warm edge lights create the
        // glossy red-and-gold game-show finish from the reference.
        if let image = Self.gradientImage(top: (0.50, 0.46, 0.50), horizon: (0.78, 0.70, 0.60), bottom: (0.11, 0.04, 0.055)),
           let env = try? EnvironmentResource(equirectangular: image, withName: "studio") {
            ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: -0.12))
        }
        root.addChild(ibl)

        let key = DirectionalLight()
        key.light.color = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        key.light.intensity = 3000
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 8, depthBias: 2)
        key.look(at: [0, 0.4, 0], from: [1.6, 4, 3], relativeTo: nil)
        root.addChild(key)

        let rim = PointLight()
        // Gold rim light separates the cast from the red background.
        rim.light.color = Self.glow
        rim.light.intensity = 145_000
        rim.light.attenuationRadius = 8
        rim.position = [-1.8, 2.2, -2.2]
        root.addChild(rim)

        let fill = PointLight()
        // A softer amber fill keeps black faces neutral and navy costumes blue while the
        // scarlet sky still supplies the warm theatrical color from the reference.
        fill.light.color = UIColor(red: 1, green: 0.58, blue: 0.32, alpha: 1)
        fill.light.intensity = 58_000
        fill.light.attenuationRadius = 7
        fill.position = [1.9, 2.0, -2.0]
        root.addChild(fill)

        // Stage, floating in the night sky.
        var stageMaterial = PhysicallyBasedMaterial()
        stageMaterial.baseColor = .init(tint: StageColors.stageSide)
        stageMaterial.roughness = 0.30
        stageMaterial.clearcoat = .init(floatLiteral: 0.82)
        let stage = ModelEntity(mesh: MeshFactory.roundedDisc(radius: 1.95, height: 0.32, bevel: 0.09), materials: [stageMaterial])
        stage.position = [0, -0.16, 0]
        root.addChild(stage)

        var topMaterial = PhysicallyBasedMaterial()
        topMaterial.baseColor = .init(tint: StageColors.stageTop)
        topMaterial.roughness = 0.22
        topMaterial.clearcoat = .init(floatLiteral: 1)
        stageTop = ModelEntity(mesh: MeshFactory.roundedDisc(radius: 1.68, height: 0.045, bevel: 0.018), materials: [topMaterial])
        stageTop.position = [0, 0.0, 0]
        root.addChild(stageTop)

        // Bright inner pool and concentric marquee rings reproduce the layered platform.
        let lightPool = ModelEntity(
            mesh: MeshFactory.roundedDisc(radius: 1.30, height: 0.018, bevel: 0.008),
            materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.58, blue: 0.10, alpha: 1))]
        )
        lightPool.position = [0, 0.035, 0]
        root.addChild(lightPool)

        let innerRing = ModelEntity(mesh: MeshFactory.torus(radius: 1.34, tube: 0.036, segments: 128, sides: 12), materials: [UnlitMaterial(color: Self.cream)])
        innerRing.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        innerRing.position = [0, 0.055, 0]
        root.addChild(innerRing)

        ring = ModelEntity(mesh: MeshFactory.torus(radius: 1.73, tube: 0.050, segments: 128, sides: 12), materials: [UnlitMaterial(color: Self.glow)])
        ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        ring.position = [0, 0.0, 0]
        root.addChild(ring)

        // Small warm bulbs around the rim add the premium game-show sparkle in the photo.
        for i in 0..<18 {
            let a = Float(i) / 18 * 2 * .pi
            let bulb = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [UnlitMaterial(color: Self.cream)])
            bulb.position = [1.58 * cos(a), 0.075, 1.58 * sin(a)]
            root.addChild(bulb)
        }

        let outer = ModelEntity(mesh: MeshFactory.torus(radius: 2.6, tube: 0.01, segments: 128, sides: 8), materials: [UnlitMaterial(color: Self.rose)])
        outer.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        outer.position = [0, -0.3, 0]
        root.addChild(outer)

        // A soft beam of light over centre stage.
        var beamMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.30, blue: 0.10, alpha: 1))
        beamMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.075))
        let beam = ModelEntity(mesh: .generateCone(height: 4.5, radius: 1.35), materials: [beamMaterial])
        beam.position = [0, 2.25, 0]
        root.addChild(beam)

        // Two broad amber side beams add the theatrical depth visible in the UI reference.
        for x: Float in [-1.75, 1.75] {
            var sideBeamMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.52, blue: 0.08, alpha: 1))
            sideBeamMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.055))
            let sideBeam = ModelEntity(mesh: .generateCone(height: 5.2, radius: 1.15), materials: [sideBeamMaterial])
            sideBeam.position = [x, 2.55, -0.7]
            root.addChild(sideBeam)
        }

        // A translucent crown silhouette anchors the stage without becoming a reused asset.
        var crownMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.08, blue: 0.20, alpha: 1))
        crownMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.24))
        let crown = ModelEntity(mesh: MeshFactory.crown(width: 4.2, height: 2.5), materials: [crownMaterial])
        crown.position = [0, 1.5, -1.9]
        root.addChild(crown)

        // Shockwave rings, recycled.
        for _ in 0..<4 {
            var m = UnlitMaterial(color: .white)
            m.blending = .transparent(opacity: .init(floatLiteral: 1))
            let wave = ModelEntity(mesh: MeshFactory.torus(radius: 1, tube: 0.012, segments: 96, sides: 6), materials: [m])
            wave.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            wave.position = [0, 0.03, 0]
            wave.components.set(OpacityComponent(opacity: 0))
            root.addChild(wave)
            shockwaves.append((wave, 10))
        }

        // Podium blocks: 2nd, 1st, 3rd from left to right.
        let blockSpecs: [(x: Float, h: Float, c: UIColor)] = [
            (-0.95, 0.38, UIColor(red: 0.75, green: 0.78, blue: 0.9, alpha: 1)),
            (0, 0.6, Self.glow),
            (0.95, 0.24, UIColor(red: 1, green: 0.28, blue: 0.45, alpha: 1)),
        ]
        for spec in blockSpecs {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: StageColors.podium)
            m.roughness = .init(floatLiteral: 0.3)
            m.clearcoat = .init(floatLiteral: 1)
            let block = ModelEntity(mesh: .generateBox(width: 0.85, height: spec.h, depth: 0.85, cornerRadius: 0.06), materials: [m])
            block.position = [spec.x, spec.h / 2, 0]
            let cap = ModelEntity(mesh: .generateBox(width: 0.87, height: 0.025, depth: 0.87, cornerRadius: 0.012), materials: [UnlitMaterial(color: spec.c)])
            cap.position = [0, spec.h / 2, 0]
            block.addChild(cap)
            podium.addChild(block)
            podiumBlocks.append(block)
        }
        podium.scale = [1, 0.001, 1]
        podium.isEnabled = false
        root.addChild(podium)

        // Floating dust motes for depth.
        let dust = Entity()
        var motes = ParticleEmitterComponent()
        motes.emitterShape = .box
        motes.emitterShapeSize = [7, 3, 4]
        motes.birthLocation = .volume
        motes.speed = 0.04
        motes.mainEmitter.birthRate = 28
        motes.mainEmitter.lifeSpan = 5
        motes.mainEmitter.size = 0.021
        motes.mainEmitter.sizeVariation = 0.014
        motes.mainEmitter.blendMode = .additive
        motes.mainEmitter.color = .constant(.random(a: .init(red: 1, green: 0.52, blue: 0.08, alpha: 0.72), b: .init(red: 1, green: 0.92, blue: 0.42, alpha: 0.62)))
        motes.mainEmitter.opacityCurve = .gradualFadeInOut
        motes.mainEmitter.noiseStrength = 0.03
        dust.components.set(motes)
        dust.position = [0, 1.4, -0.5]
        root.addChild(dust)

        confetti.position = [0, 3.2, 0.3]
        root.addChild(confetti)

        camera.camera.fieldOfViewInDegrees = 38
        camera.look(at: cameraTarget, from: cameraPosition, relativeTo: nil)
        root.addChild(camera)

        for entity in [stage, stageTop] + podiumBlocks {
            entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        }
    }

    // MARK: State sync

    func sync(_ new: StageState) {
        let old = state
        state = new

        // Keep one rig per player.
        let ids = Set(new.members.map(\.id))
        for (id, rig) in rigs where !ids.contains(id) {
            rig.root.removeFromParent()
            rigs[id] = nil
        }
        for (i, member) in new.members.enumerated() {
            if rigs[member.id]?.character != member.character,
               let template = templates[member.character] {
                // New player, or a character swap: the new rig takes the old one's spot.
                let rig = MascotRig(template: template, character: member.character,
                                    seed: Double(i) * 1.37 + 0.4)
                rig.light(with: ibl)
                root.addChild(rig.root)
                if let old = rigs[member.id] {
                    rig.takeOver(from: old)
                    old.root.removeFromParent()
                }
                rigs[member.id] = rig
            }
        }

        var newShowcase: [MascotRig] = []
        for (i, kind) in CharacterKind.allCases.enumerated() {
            if showcase[kind] == nil, let template = templates[kind] {
                let rig = MascotRig(template: template, character: kind, seed: Double(i) * 0.91 + 2.3)
                rig.light(with: ibl)
                root.addChild(rig.root)
                showcase[kind] = rig
                newShowcase.append(rig)
            }
        }

        let turnScreens: Set<Screen> = [.handoff, .turn, .reveal]
        let player = new.members.first { $0.id == new.focusID }?.color
        let ringColor = turnScreens.contains(new.screen) ? (player?.uiColor ?? Self.glow) : Self.glow
        if ringColor != accent {
            accent = ringColor
            ring.model?.materials = [UnlitMaterial(color: ringColor)]
        }

        layout()
        // The lineup appears already in place (no walking out from the middle on launch).
        for rig in newShowcase { rig.settle() }

        if new.beat != old.beat { focusRig?.beat(); emitShockwave(strength: 0.6) }
        if new.pokes != old.pokes {
            let target = new.screen == .home ? showcase[new.homeCharacter] : focusRig
            (new.pokeID.flatMap { rigs[$0] } ?? target)?.poke()
            emitShockwave(strength: 0.8)
        }
        if new.screen != old.screen {
            if new.screen == .podium { burstConfetti() }
            if [.handoff, .reveal].contains(new.screen) { focusRig?.hop(1.1); emitShockwave(strength: 1) }
            if new.screen == .reveal, new.mood == .happy { burstConfetti(small: true) }
        }
    }

    private var focusRig: MascotRig? {
        state.focusID.flatMap { rigs[$0] }
    }

    /// Which lineup character an entity belongs to, if any (home screen taps).
    func showcaseKind(for entity: Entity) -> CharacterKind? {
        var e: Entity? = entity
        while let current = e {
            if let kind = showcase.first(where: { $0.value.root === current })?.key { return kind }
            e = current.parent
        }
        return nil
    }

    func memberID(for entity: Entity) -> UUID? {
        var e: Entity? = entity
        while let current = e {
            if let id = rigs.first(where: { $0.value.root === current })?.key { return id }
            e = current.parent
        }
        return nil
    }

    /// Positions every rig for the current screen and sets the camera goal.
    private func layout() {
        let members = state.members
        let count = members.count
        let focus = state.focusID

        func lineup(_ order: [UUID], spacing: Float, scale: Float, z: Float = 0) {
            let width = spacing * Float(max(order.count - 1, 0))
            for (i, id) in order.enumerated() {
                guard let rig = rigs[id] else { continue }
                let x = -width / 2 + Float(i) * spacing
                rig.placement = [x, 0, z - abs(x) * 0.28]
                rig.scale = scale
                rig.facing = -x * 0.18
            }
        }

        // Everyone else watches from the wings, alternating right and left.
        func audience(except front: UUID?) {
            let others = members.map(\.id).filter { $0 != front }
            for (i, id) in others.enumerated() {
                guard let rig = rigs[id] else { continue }
                let side: Float = i % 2 == 0 ? 1 : -1
                let row = Float(i / 2)
                rig.placement = [side * (1.0 + row * 0.45), 0, -0.45 - row * 0.45]
                rig.scale = 0.62 - row * 0.06
                rig.facing = -side * 0.45
                rig.dimmed = true
            }
        }

        func lineupSpacing() -> (spacing: Float, scale: Float) {
            count > 5 ? (0.62, 0.66) : (count > 3 ? (0.8, 0.82) : (0.95, 1))
        }

        for rig in rigs.values { rig.dimmed = false }
        if state.screen != .home {
            for rig in showcase.values { rig.scale = 0 }
        }
        podium.isEnabled = state.screen == .podium
        podiumRise.target = state.screen == .podium ? 1 : 0

        switch state.screen {
        case .home:
            // Players step aside; the lineup takes the stage. The host's pick stands in
            // the middle with its neighbours either side, turned in toward it.
            for rig in rigs.values {
                rig.placement = [0, 0, -1.6]
                rig.scale = 0
            }
            let kinds = CharacterKind.allCases
            let selected = kinds.firstIndex(of: state.homeCharacter) ?? 0
            for (i, kind) in kinds.enumerated() {
                guard let rig = showcase[kind] else { continue }
                var rel = i - selected
                if rel > kinds.count / 2 { rel -= kinds.count }
                if rel < -kinds.count / 2 { rel += kinds.count }
                let side = Float(rel.signum())
                switch abs(rel) {
                case 0:
                    rig.placement = [0, 0.26, 0.22]; rig.scale = 1.30; rig.facing = 0
                case 1:
                    rig.placement = [side * 0.92, 0.14, -0.62]; rig.scale = 0.74; rig.facing = -side * 0.45
                default:
                    rig.placement = [side * 1.8, 0, -1.1]; rig.scale = 0; rig.facing = 0
                }
                rig.mood = .idle
            }
            setCamera(position: [0, 1.4, 6.0], target: [0, 0.28, 0])

        case .crew, .packs:
            let (spacing, scale) = lineupSpacing()
            lineup(members.map(\.id), spacing: spacing, scale: scale)
            for (id, rig) in rigs {
                rig.mood = state.screen == .packs ? .happy : .idle
                if id == focus, state.screen == .crew {
                    rig.placement.z += 0.35
                    rig.scale = scale * 1.15
                }
            }
            let wide = Float(count) * spacing * 0.5
            setCamera(position: [0, 1.7, 6.6 + wide * 1.1], target: [0, -0.7 - wide * 0.1, 0])

        case .handoff, .turn, .reveal:
            audience(except: focus)
            if let focus, let rig = rigs[focus] {
                rig.placement = [0, 0, 0.25]
                rig.scale = 1.15
                rig.facing = 0
                rig.mood = state.mood
            }
            for (id, rig) in rigs where id != focus { rig.mood = state.audienceMood }
            if state.screen == .turn {
                setCamera(position: [0, 1.2, 6.0], target: [0, 0.02, 0])
            } else {
                setCamera(position: [0, 1.4, 6.2], target: [0, -0.2, 0])
            }

        case .recap:
            let (spacing, scale) = lineupSpacing()
            // Leader in the middle, the rest alternating outwards by rank.
            var order: [UUID] = []
            for (i, id) in state.ranking.enumerated() {
                if i % 2 == 0 { order.append(id) } else { order.insert(id, at: 0) }
            }
            lineup(order, spacing: spacing, scale: scale)
            for (id, rig) in rigs {
                rig.mood = id == state.ranking.first ? .celebrate : .idle
                if id == state.ranking.first { rig.placement.z += 0.3; rig.scale = scale * 1.15 }
            }
            let wide = Float(count) * spacing * 0.5
            setCamera(position: [0, 1.7, 6.6 + wide * 1.1], target: [0, -0.7 - wide * 0.1, 0])

        case .podium:
            let spots: [SIMD3<Float>] = [[0, 0.6, 0], [-0.95, 0.38, 0], [0.95, 0.24, 0]]
            let rest = Array(state.ranking.dropFirst(3))
            for (i, id) in state.ranking.enumerated() {
                guard let rig = rigs[id] else { continue }
                if i < 3 {
                    rig.placement = spots[i]
                    rig.scale = i == 0 ? 0.95 : 0.8
                    rig.facing = -spots[i].x * 0.2
                    rig.mood = i == 0 ? .celebrate : .happy
                } else {
                    let j = Float(rest.firstIndex(of: id) ?? 0)
                    let x = (j - Float(rest.count - 1) / 2) * 0.62
                    rig.placement = [x, 0, -1.4]
                    rig.scale = 0.5
                    rig.facing = 0
                    rig.mood = .happy
                    rig.dimmed = true
                }
            }
            setCamera(position: [0, 1.6, 8.5], target: [0, -0.1, 0])
        }
    }

    private func setCamera(position: SIMD3<Float>, target: SIMD3<Float>) {
        cameraGoal = (position, target)
    }

    private var cameraGoal: (SIMD3<Float>, SIMD3<Float>) = ([0, 1.0, 3.6], [0, 0.05, 0])

    // MARK: Frame loop

    func tick(_ dt: Float) {
        let dt = min(dt, 1 / 20)
        time += Double(dt)
        let level = Float(level())

        for rig in rigs.values {
            rig.update(dt: dt, time: time, level: rig === focusRig ? level : 0)
        }
        for rig in showcase.values {
            rig.update(dt: dt, time: time, level: 0)
        }

        // Camera glides toward its goal with a gentle idle drift.
        let k = min(1, 2.6 * dt)
        cameraPosition += (cameraGoal.0 - cameraPosition) * k
        cameraTarget += (cameraGoal.1 - cameraTarget) * k
        let drift: SIMD3<Float> = reduceMotion ? .zero : [sin(Float(time) * 0.21) * 0.08, sin(Float(time) * 0.17) * 0.04, 0]
        camera.look(at: cameraTarget, from: cameraPosition + drift, relativeTo: nil)

        // Voice peaks ripple out across the stage.
        if level > 0.45, time - lastLevelPeak > 0.22 {
            lastLevelPeak = time
            emitShockwave(strength: level)
        }
        let ringPulse = 1 + level * 0.06
        ring.scale = [ringPulse, ringPulse, ringPulse]

        for i in shockwaves.indices {
            shockwaves[i].age += dt
            let age = shockwaves[i].age
            let e = shockwaves[i].entity
            if age < 1.1 {
                let r = 0.5 + age * 1.9
                e.scale = [r, r, r]
                e.components.set(OpacityComponent(opacity: max(0, 0.75 * (1 - age / 1.1))))
            } else if e.isEnabled {
                e.isEnabled = false
            }
        }

        podiumRise.step(dt)
        podium.scale = [1, max(0.001, podiumRise.value), 1]
    }

    private func emitShockwave(strength: Float) {
        guard !reduceMotion, let i = shockwaves.indices.max(by: { shockwaves[$0].age < shockwaves[$1].age }) else { return }
        shockwaves[i].age = 0
        let e = shockwaves[i].entity
        e.isEnabled = true
        e.model?.materials = [{
            var m = UnlitMaterial(color: accent)
            m.blending = .transparent(opacity: .init(floatLiteral: max(0.3, min(1, strength))))
            return m
        }()]
    }

    private func burstConfetti(small: Bool = false) {
        guard !reduceMotion else { return }
        confetti.children.removeAll()
        // Show palette: marquee gold, orange, bright red and cream.
        let red = UIColor(red: 1, green: 0.14, blue: 0.20, alpha: 1)
        let pairs: [(UIColor, UIColor)] = [(Self.gold, Self.glow), (red, Self.cream), (Self.gold, red)]
        for (a, b) in pairs {
            let e = Entity()
            var p = ParticleEmitterComponent()
            p.emitterShape = .box
            p.emitterShapeSize = [small ? 1.5 : 3.2, 0.1, 1]
            p.birthLocation = .volume
            p.timing = .once(warmUp: nil, emit: .init(duration: small ? 0.15 : 0.35))
            p.speed = 0.6
            p.speedVariation = 0.4
            p.emissionDirection = [0, 1, 0]
            p.mainEmitter.birthRate = small ? 300 : 900
            p.mainEmitter.lifeSpan = 3.2
            p.mainEmitter.size = 0.035
            p.mainEmitter.sizeVariation = 0.015
            p.mainEmitter.acceleration = [0, -1.6, 0]
            p.mainEmitter.dampingFactor = 1.2
            p.mainEmitter.spreadingAngle = 1.2
            p.mainEmitter.angularSpeed = 4
            p.mainEmitter.angularSpeedVariation = 3
            p.mainEmitter.billboardMode = .free(axis: [0.3, 1, 0.2], variation: 1)
            p.mainEmitter.color = .constant(.random(a: a, b: b))
            p.mainEmitter.isLightingEnabled = false
            p.mainEmitter.noiseStrength = 0.4
            p.mainEmitter.noiseScale = 1
            e.components.set(p)
            confetti.addChild(e)
        }
    }

    // MARK: Environment

    /// A vertical gradient as an equirectangular image for image-based lighting.
    private static func gradientImage(top: (CGFloat, CGFloat, CGFloat), horizon: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat)) -> CGImage? {
        let w = 256, h = 128
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [top, horizon, bottom].map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.48, 1]) else { return nil }
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        return ctx.makeImage()
    }
}
