import RealityKit
import simd

/// Procedural meshes the built-in primitives don't cover.
@MainActor
enum MeshFactory {
    /// Revolves a profile around the Y axis. `profile` maps t in 0...1 (bottom to top)
    /// to (radius, height).
    static func lathe(segments: Int = 48, rings: Int = 40, profile: (Float) -> (r: Float, y: Float)) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let points = (0...rings).map { profile(Float($0) / Float(rings)) }
        for (i, p) in points.enumerated() {
            // Profile tangent → outward normal in the (r, y) plane.
            let prev = points[max(i - 1, 0)], next = points[min(i + 1, rings)]
            let tangent = SIMD2<Float>(next.r - prev.r, next.y - prev.y)
            var n2 = SIMD2<Float>(tangent.y, -tangent.x)
            n2 = simd_length(n2) > 1e-6 ? simd_normalize(n2) : SIMD2(0, i == 0 ? -1 : 1)
            for s in 0...segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                let c = cos(a), sn = sin(a)
                positions.append([p.r * c, p.y, p.r * sn])
                normals.append(simd_normalize([n2.x * c, n2.y, n2.x * sn]))
            }
        }
        let stride = UInt32(segments + 1)
        for i in 0..<UInt32(rings) {
            for s in 0..<UInt32(segments) {
                let a = i * stride + s, b = a + stride
                indices += [a, a + 1, b, b, a + 1, b + 1]
            }
        }
        return build(positions, normals, indices)
    }

    /// A torus in the XY plane (ring around the Z axis), optionally just an arc.
    static func torus(radius: Float, tube: Float, arc: Float = 2 * .pi, segments: Int = 64, sides: Int = 16) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let start = (2 * .pi - arc) / 2 + .pi / 2 - .pi
        for i in 0...segments {
            let u = start + Float(i) / Float(segments) * arc
            let center = SIMD3<Float>(radius * cos(u), radius * sin(u), 0)
            for j in 0...sides {
                let v = Float(j) / Float(sides) * 2 * .pi
                let n = SIMD3<Float>(cos(v) * cos(u), cos(v) * sin(u), sin(v))
                positions.append(center + n * tube)
                normals.append(n)
            }
        }
        let stride = UInt32(sides + 1)
        for i in 0..<UInt32(segments) {
            for j in 0..<UInt32(sides) {
                let a = i * stride + j, b = a + stride
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        return build(positions, normals, indices)
    }

    /// A rounded disc: flat top and bottom with a soft bevel, centred on the origin.
    static func roundedDisc(radius: Float, height: Float, bevel: Float) -> MeshResource {
        let h = height / 2, inner = radius - bevel
        // Bottom cap → lower bevel → wall → upper bevel → top cap.
        var points: [(r: Float, y: Float)] = [(0, -h), (inner * 0.5, -h)]
        for k in 0...6 {
            let a = Float(k) / 6 * (.pi / 2)
            points.append((inner + bevel * sin(a), -h + bevel - bevel * cos(a)))
        }
        for k in 0...6 {
            let a = Float(k) / 6 * (.pi / 2)
            points.append((inner + bevel * cos(a), h - bevel + bevel * sin(a)))
        }
        points += [(inner * 0.5, h), (0, h)]
        return lathe(segments: 72, rings: points.count - 1) { t in points[Int((t * Float(points.count - 1)).rounded())] }
    }

    /// Flat crown silhouette used as an original stage backdrop. It faces the camera on
    /// the XY plane and deliberately stays low-poly to match the characters.
    static func crown(width: Float, height: Float) -> MeshResource {
        let w = width / 2, h = height / 2
        let outline: [SIMD3<Float>] = [
            [-w, -h, 0], [-w, -h * 0.12, 0], [-w * 0.58, h * 0.72, 0],
            [-w * 0.18, h * 0.05, 0], [0, h, 0], [w * 0.18, h * 0.05, 0],
            [w * 0.58, h * 0.72, 0], [w, -h * 0.12, 0], [w, -h, 0],
        ]
        var positions = [SIMD3<Float>(0, -h * 0.28, 0)] + outline
        var normals = Array(repeating: SIMD3<Float>(0, 0, 1), count: positions.count)
        var indices: [UInt32] = []
        for i in 1...outline.count {
            let next = i == outline.count ? 1 : i + 1
            indices += [0, UInt32(i), UInt32(next)]
        }
        return build(positions, normals, indices)
    }

    private static func build(_ positions: [SIMD3<Float>], _ normals: [SIMD3<Float>], _ indices: [UInt32]) -> MeshResource {
        var d = MeshDescriptor()
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [d])
    }
}
