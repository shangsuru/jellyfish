import simd

/// 各解剖学的部位のパラメトリックメッシュを構築する。
///
/// 頂点はパラメトリック座標のみを保持し、
/// Jellyfish.metal の頂点シェーダが毎フレームそれをアニメーションする位置へ変換する。
enum JellyfishMeshBuilder {

    /// 傘のグリッド。p0 = (u, θ)。2インスタンス（外面と内面）で描画する。
    static func bell(_ a: JellyfishAnatomy) -> MeshData {
        var mesh = MeshData()
        let nu = a.bellRadialSegments, nt = a.bellAngularSegments
        for i in 0...nu {
            let x = Float(i) / Float(nu)
            // 繊細な傘縁に向かってリングをやや密にする。
            let u = 1 - pow(1 - x, 1.25)
            for j in 0...nt {
                let theta = Float(j) / Float(nt) * 2 * .pi
                mesh.vertices.append(PartVertex(p0: SIMD4(u, theta, 0, 0)))
            }
        }
        mesh.appendGrid(rows: nu, cols: nt, baseVertex: 0)
        return mesh
    }

    /// 生殖腺。p0 = (生殖腺インデックス, 馬蹄形に沿った s, 断面角度)。
    static func gonads(_ a: JellyfishAnatomy) -> MeshData {
        var mesh = MeshData()
        let ns = 120, na = 16
        for g in 0..<a.gonadCount {
            let base = mesh.vertices.count
            for i in 0...ns {
                for j in 0...na {
                    let s = Float(i) / Float(ns)
                    let ang = Float(j) / Float(na) * 2 * .pi
                    mesh.vertices.append(PartVertex(p0: SIMD4(Float(g), s, ang, 0)))
                }
            }
            mesh.appendGrid(rows: ns, cols: na, baseVertex: base)
        }
        return mesh
    }

    /// 口柄の筒。p0 = (柄に沿った s, 角度)。
    static func manubrium(_ a: JellyfishAnatomy) -> MeshData {
        var mesh = MeshData()
        let ns = 24, na = 48
        for i in 0...ns {
            for j in 0...na {
                let s = Float(i) / Float(ns)
                let ang = Float(j) / Float(na) * 2 * .pi
                mesh.vertices.append(PartVertex(p0: SIMD4(s, ang, 0, 0)))
            }
        }
        mesh.appendGrid(rows: ns, cols: na, baseVertex: 0)
        return mesh
    }

    /// 口腕のシート。p0 = (口腕インデックス, 口腕に沿った s, 横方向の w)、p1.x = シード。
    static func oralArms(_ a: JellyfishAnatomy, rng: inout SeededRandom) -> MeshData {
        var mesh = MeshData()
        let ns = a.oralArmLengthSegments, nw = a.oralArmWidthSegments
        for arm in 0..<a.oralArmCount {
            let seed = rng.next()
            let base = mesh.vertices.count
            for i in 0...ns {
                for j in 0...nw {
                    let s = Float(i) / Float(ns)
                    let w = Float(j) / Float(nw) * 2 - 1
                    mesh.vertices.append(PartVertex(p0: SIMD4(Float(arm), s, w, 0),
                                                    p1: SIMD4(seed, 0, 0, 0)))
                }
            }
            mesh.appendGrid(rows: ns, cols: nw, baseVertex: base)
        }
        return mesh
    }

    /// 触手のリボン。p0 = (インデックス, s, 側 ±1)、p1 = (付け根の θ, 長さ, 半径, シード)。
    static func tentacles(_ a: JellyfishAnatomy, rng: inout SeededRandom) -> MeshData {
        var mesh = MeshData()
        var index = 0

        func addTentacle(theta: Float, length: Float, radius: Float, segments: Int) {
            let base = mesh.vertices.count
            let seed = rng.next()
            for i in 0...segments {
                let s = Float(i) / Float(segments)
                for side: Float in [-1, 1] {
                    mesh.vertices.append(PartVertex(p0: SIMD4(Float(index), s, side, 0),
                                                    p1: SIMD4(theta, length, radius, seed)))
                }
            }
            mesh.appendGrid(rows: segments, cols: 1, baseVertex: base)
            index += 1
        }

        // 長い触手は縁弁の下から、わずかな不規則さを持たせて等間隔に生える。
        for i in 0..<a.longTentacleCount {
            let step = 2 * Float.pi / Float(a.longTentacleCount)
            let theta = (Float(i) + 0.5 + rng.next(in: -0.2...0.2)) * step
            addTentacle(theta: theta,
                        length: rng.next(in: a.longTentacleLength),
                        radius: a.longTentacleRadius * rng.next(in: 0.8...1.2),
                        segments: a.longTentacleSegments)
        }
        // 短い触手の密な縁取りが傘縁全体に並ぶ。
        for i in 0..<a.fringeTentacleCount {
            let step = 2 * Float.pi / Float(a.fringeTentacleCount)
            let theta = (Float(i) + rng.next(in: -0.3...0.3)) * step
            addTentacle(theta: theta,
                        length: rng.next(in: a.fringeTentacleLength),
                        radius: a.fringeTentacleRadius * rng.next(in: 0.8...1.2),
                        segments: a.fringeTentacleSegments)
        }
        return mesh
    }

    /// 浮遊粒子用のビルボード四角形。
    /// p0 = (基準位置, サイズ)、p1 = (角, シード, 明るさ)。
    static func particles(count: Int, extent: Float, rng: inout SeededRandom) -> MeshData {
        var mesh = MeshData()
        let corners: [SIMD2<Float>] = [[-1, -1], [1, -1], [-1, 1], [1, 1]]
        for _ in 0..<count {
            let p = SIMD3(rng.next(in: -0.5...0.5), rng.next(in: -0.5...0.5), rng.next(in: -0.5...0.5)) * extent
            let size = rng.next(in: 0.006...0.022)
            let seed = rng.next()
            let brightness = rng.next(in: 0.05...0.25)
            let base = UInt32(mesh.vertices.count)
            for c in corners {
                mesh.vertices.append(PartVertex(p0: SIMD4(p, size), p1: SIMD4(c.x, c.y, seed, brightness)))
            }
            mesh.indices += [base, base + 1, base + 2, base + 2, base + 1, base + 3]
        }
        return mesh
    }
}

/// 起動のたびに標本が同じ見た目になるよう、決定的な SplitMix64 乱数生成器を使う。
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 24)
    }

    mutating func next(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }
}
