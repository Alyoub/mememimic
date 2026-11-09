import RealityKit
import UIKit
import simd

/// Damped spring used for every procedural channel on the mascot.
struct Spring {
    var value: Float
    var target: Float
    var velocity: Float = 0
    var stiffness: Float = 140
    var damping: Float = 16

    init(_ value: Float, stiffness: Float = 140, damping: Float = 16) {
        self.value = value
        self.target = value
        self.stiffness = stiffness
        self.damping = damping
    }

    mutating func step(_ dt: Float) {
        velocity += (stiffness * (target - value) - damping * velocity) * dt
        value += velocity * dt
    }
}

/// One player's character: a Quaternius model (CC0) cloned per player. Every character
/// keeps the authored colors from its source file.
///
/// Two layers drive it. Skeletal clips baked in Blender (Models/<Character>.usdz, exported
/// by art/export_mascot.py) carry the body language: idle, walk, jump, victory, defeat and
/// a hit reaction. On top, springs handle what the clips can't know about: stage placement,
/// hops on the beat, squash with the microphone level, and leaning in to listen.
@MainActor
final class MascotRig {
    /// Clip time ranges on the exported timeline, in seconds. Every character shares
    /// them; they must match the CLIP lines printed by art/export_mascot.py.
    enum Clip: CaseIterable {
        case idle, walk, jump, victory, defeat, hit

        var range: (start: Double, end: Double) {
            switch self {
            case .idle: (0.0, 4.1667)
            case .walk: (4.25, 5.5)
            case .jump: (5.5833, 6.625)
            case .victory: (6.7083, 8.5833)
            case .defeat: (8.6667, 11.1667)
            case .hit: (11.25, 11.875)
            }
        }

        var loops: Bool { self != .defeat && self != .hit }
    }

    /// The source bodies are ~3.1 m tall; this brings them to ~1.05 m on stage.
    static let modelScale: Float = 0.335

    let root = Entity()
    let character: CharacterKind

    private let mover = Entity()      // stage position, facing, size
    private let hopper = Entity()     // procedural hop, squash and lean
    private let model: Entity
    private let skinned: ModelEntity?
    private var clips: [Clip: AnimationResource] = [:]
    private var playing: Clip?
    private var reactingUntil: Double = 0
    private var time: Double = 0

    // Animation state
    var mood: MascotMood = .idle
    var placement = SIMD3<Float>(0, 0, 0)
    var scale: Float = 1
    var facing: Float = 0
    var dimmed = false
    private var x = Spring(0, stiffness: 60, damping: 13)
    private var z = Spring(0, stiffness: 60, damping: 13)
    private var size = Spring(0, stiffness: 90, damping: 12)
    private var yaw = Spring(0, stiffness: 50, damping: 10)
    private var spin: Float = 0
    private var spinVelocity: Float = 0
    private var squash = Spring(0, stiffness: 260, damping: 11)
    private var leanZ = Spring(0, stiffness: 70, damping: 10)
    private var leanX = Spring(0, stiffness: 70, damping: 10)
    private var hopY: Float = 0
    private var hopVelocity: Float = 0
    private let seed: Double

    init(template: Entity, character: CharacterKind, seed: Double) {
        self.character = character
        self.seed = seed
        model = template.clone(recursive: true)
        // The exporter adds a light of its own; the stage does the lighting.
        model.findEntity(named: "env_light")?.removeFromParent()
        model.scale = .init(repeating: Self.modelScale)

        var found: ModelEntity?
        model.visit { if found == nil, let m = $0 as? ModelEntity, !m.availableAnimations.isEmpty { found = m } }
        skinned = found

        hopper.addChild(model)
        mover.addChild(hopper)
        root.addChild(mover)

        if let source = skinned?.availableAnimations.first?.definition {
            for clip in Clip.allCases {
                let view = AnimationView(source: source,
                                         repeatMode: clip.loops ? .repeat : .none,
                                         fillMode: clip.loops ? [] : .forwards,
                                         trimStart: clip.range.start,
                                         trimEnd: clip.range.end)
                clips[clip] = try? AnimationResource.generate(with: view)
            }
        }
        polishMaterials()
        play(.idle, blend: 0)

        let shape = ShapeResource.generateBox(width: 0.6, height: 1.1, depth: 0.5).offsetBy(translation: [0, 0.55, 0])
        root.components.set(CollisionComponent(shapes: [shape]))
        root.components.set(InputTargetComponent())
        root.name = "mascot"
        mover.scale = .zero
    }

    /// Rich game-show color grade. Geometry stays exactly as authored: only the material
    /// finish changes so black faces stay black, pale pieces become warm cream, and the
    /// navy/red/brown/gold costumes read clearly against the scarlet stage.
    private func polishMaterials() {
        guard let skinned, let materials = skinned.model?.materials else { return }
        skinned.model?.materials = materials.map { material in
            guard var m = material as? PhysicallyBasedMaterial else { return material }
            let isEye = m.roughness.scale <= 0.15
            m.roughness = .init(floatLiteral: isEye ? 0.09 : min(m.roughness.scale, 0.38))
            m.clearcoat = .init(floatLiteral: isEye ? 0.82 : 0.18)
            m.clearcoatRoughness = .init(floatLiteral: isEye ? 0.06 : 0.20)
            var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if m.baseColor.tint.getHue(&h, saturation: &sat, brightness: &b, alpha: &a) {
                if isEye, b > 0.45 {
                    // The reference uses glossy cream eye whites rather than harsh white.
                    m.baseColor.tint = UIColor(red: 1.0, green: 0.95, blue: 0.84, alpha: a)
                } else if b < 0.32, sat < 0.20 {
                    // Preserve the cast's defining neutral-black faces, hands, hats and
                    // pupils. Their source black is stored in linear color, so its decoded
                    // brightness can be higher than it first appears.
                    m.baseColor.tint = UIColor(red: 0.010, green: 0.009, blue: 0.012, alpha: a)
                    m.clearcoat = .init(floatLiteral: isEye ? 0.82 : 0.07)
                } else if sat < 0.12, b > 0.55 {
                    // White clothing and trim share the same warm cream as the UI type.
                    m.baseColor.tint = UIColor(red: 1.0, green: 0.95, blue: 0.86, alpha: a)
                } else if h > 0.55, h < 0.82 {
                    // The warm stage can pull authored navy toward purple; bias it toward
                    // a rich royal navy so it lands on the reference color under lighting.
                    m.baseColor.tint = UIColor(hue: 0.60,
                                               saturation: max(0.82, min(1, sat * 1.25)),
                                               brightness: max(0.27, min(0.38, b * 1.02)),
                                               alpha: a)
                } else {
                    // Add color density without pushing cloth and leather toward pastel.
                    m.baseColor.tint = UIColor(hue: h,
                                               saturation: min(1, sat * 1.38 + 0.035),
                                               brightness: min(0.94, b * 1.10 + 0.055),
                                               alpha: a)
                }
            }
            return m
        }
    }

    /// Applies image-based lighting and contact shadows to every model in the rig.
    func light(with ibl: Entity) {
        root.visit { entity in
            guard entity is ModelEntity else { return }
            entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
    }

    private func play(_ clip: Clip, blend: TimeInterval = 0.25) {
        guard clip != playing, let skinned, let resource = clips[clip] else { return }
        playing = clip
        skinned.playAnimation(resource, transitionDuration: blend, startsPaused: false)
    }

    /// Stands the rig at its placement immediately, facing the right way, instead of
    /// walking there from the middle of the stage (used for rigs created mid-scene).
    func settle() {
        x.value = placement.x; z.value = placement.z
        x.velocity = 0; z.velocity = 0
        yaw.value = facing; yaw.velocity = 0
    }

    /// Continues from another rig's spot on stage (used when a player swaps character).
    func takeOver(from other: MascotRig) {
        x = other.x; z = other.z; yaw = other.yaw
        size.value = other.size.value * 0.6
        hop(0.9)
        spinVelocity += 10
    }

    // MARK: Reactions

    func poke() {
        hop(1.1)
        spinVelocity += 12
        squash.velocity += 4
        reactingUntil = time + 0.6
        playing = nil
        play(.hit, blend: 0.1)
    }

    func beat() {
        squash.velocity += 3.5
    }

    func hop(_ strength: Float = 1) {
        guard hopY <= 0.001 else { return }
        squash.velocity += 3
        hopVelocity = 2.0 * strength
    }

    // MARK: Frame update

    func update(dt: Float, time t: Double, level: Float) {
        time = t
        let ft = Float(t + seed)

        // Body language from the skeletal clips.
        let moving = abs(x.velocity) + abs(z.velocity) > 0.35
        if t >= reactingUntil {
            switch mood {
            case .happy: play(.jump)
            case .celebrate: play(.victory)
            case .sad: play(.defeat)
            default: play(moving ? .walk : .idle)
            }
        }

        // Procedural layer on top.
        var breath: Float = 0, lz: Float = 0, lx: Float = 0
        switch mood {
        case .listening:
            lz = 0.12 + sin(ft * 3) * 0.04       // head cocked toward the sound
            lx = 0.06
            breath = abs(sin(ft * 3)) * 0.03
        case .ready:
            breath = abs(sin(ft * 6)) * 0.03
        case .recording:
            breath = -level * 0.12               // stretch tall with the voice
            lx = -0.08 - level * 0.08            // lean into the mic
            lz = sin(ft * 9) * 0.05 * level
        case .thinking:
            lz = 0.08 + sin(ft * 1.2) * 0.04
        default:
            break
        }

        let steps = max(1, Int(ceil(dt / (1 / 120))))
        let h = dt / Float(steps)
        x.target = placement.x; z.target = placement.z
        size.target = scale; yaw.target = facing
        squash.target = breath
        leanZ.target = lz; leanX.target = lx
        for _ in 0..<steps {
            x.step(h); z.step(h); size.step(h); yaw.step(h)
            squash.step(h); leanZ.step(h); leanX.step(h)
            if hopY > 0 || hopVelocity > 0 {
                hopVelocity -= 9.8 * h
                hopY += hopVelocity * h
                if hopY <= 0 {
                    hopY = 0
                    squash.velocity += min(4, abs(hopVelocity) * 1.6)
                    hopVelocity = 0
                }
            }
            spin += spinVelocity * h
            spinVelocity *= max(0, 1 - 2.8 * h)
        }
        if abs(spinVelocity) < 1.5 {
            let rest = (spin / (2 * .pi)).rounded() * 2 * .pi
            spin += (rest - spin) * min(1, 6 * dt)
        }

        // Fully shrunk rigs (players offstage, unused lineup slots) stop rendering.
        root.isEnabled = scale > 0 || size.value > 0.01

        // Face the direction of travel while walking, otherwise the stage facing.
        let heading = moving ? atan2(x.velocity, z.velocity) : yaw.value
        mover.position = [x.value, placement.y, z.value]
        mover.scale = .init(repeating: max(0, size.value))
        mover.orientation = simd_quatf(angle: heading + spin, axis: [0, 1, 0])

        let s = squash.value
        hopper.position = [0, hopY, 0]
        hopper.scale = [1 + s * 0.5, 1 - s, 1 + s * 0.5]
        hopper.orientation = simd_quatf(angle: leanZ.value, axis: [0, 0, 1]) * simd_quatf(angle: leanX.value, axis: [1, 0, 0])
    }
}

extension Entity {
    func visit(_ body: (Entity) -> Void) {
        body(self)
        for child in children { child.visit(body) }
    }
}
