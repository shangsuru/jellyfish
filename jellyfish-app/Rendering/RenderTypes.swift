import simd

// GPU 向けのデータレイアウト。Shaders/ShaderCommon.h の構造体と
// 完全に一致させる必要がある。すべてのフィールドを float4 か float4x4 にし、
// Swift と Metal でアライメントが予期せぬパディングなく一致するようにしている。

struct FrameUniforms {
    var viewProj: simd_float4x4
    var view: simd_float4x4
    var invViewProj: simd_float4x4
    var cameraPos: SIMD4<Float>       // xyz 位置、w 時刻
    var viewport: SIMD4<Float>        // 幅、高さ、ピクセル角、焦点距離
    var keyLightDir: SIMD4<Float>
    var keyLightColor: SIMD4<Float>
    var fillLightDir: SIMD4<Float>
    var fillLightColor: SIMD4<Float>
    var ambientTop: SIMD4<Float>
    var ambientBottom: SIMD4<Float>
    var anim: SIMD4<Float>            // 周期、収縮量、揺れ、遅延
    var current: SIMD4<Float>
}

struct AnatomyUniforms {
    var bell: SIMD4<Float>
    var bell2: SIMD4<Float>
    var gonad: SIMD4<Float>
    var oralArm: SIMD4<Float>
    var tentacle: SIMD4<Float>
    var manubrium: SIMD4<Float>
}

struct MaterialUniforms {
    var baseColor: SIMD4<Float>
    var rimColor: SIMD4<Float>
    var detailColor: SIMD4<Float>
    var accentColor: SIMD4<Float>
    var params: SIMD4<Float>          // フレネル指数、散乱、鏡面反射、透過
}

/// 汎用のパラメトリック頂点。各部位の頂点シェーダが
/// 2つの成分をそれぞれ異なる意味で解釈する（JellyfishMeshBuilder を参照）。
struct PartVertex {
    var p0: SIMD4<Float>
    var p1: SIMD4<Float> = .zero
}

/// アップロード前の CPU 側メッシュ。
struct MeshData {
    var vertices: [PartVertex] = []
    var indices: [UInt32] = []

    /// (rows+1)×(cols+1) の頂点グリッドの三角形インデックスを追加する。
    mutating func appendGrid(rows: Int, cols: Int, baseVertex: Int) {
        let stride = cols + 1
        for i in 0..<rows {
            for j in 0..<cols {
                let a = UInt32(baseVertex + i * stride + j)
                let b = a + UInt32(stride)
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
    }
}

extension simd_float4x4 {
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        ))
    }

    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t, 1)
        return m
    }
}
