import simd

// GPU-facing data layouts. These must match the structs in
// Shaders/ShaderCommon.h exactly; every field is a float4 or float4x4
// so Swift and Metal agree on alignment without padding surprises.

struct FrameUniforms {
    var viewProj: simd_float4x4
    var view: simd_float4x4
    var invViewProj: simd_float4x4
    var cameraPos: SIMD4<Float>       // xyz position, w time
    var viewport: SIMD4<Float>        // width, height, pixel angle, focus distance
    var keyLightDir: SIMD4<Float>
    var keyLightColor: SIMD4<Float>
    var fillLightDir: SIMD4<Float>
    var fillLightColor: SIMD4<Float>
    var ambientTop: SIMD4<Float>
    var ambientBottom: SIMD4<Float>
    var anim: SIMD4<Float>            // period, contraction, sway, lag
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
    var params: SIMD4<Float>          // fresnel power, scatter, specular, transmission
}

/// Generic parametric vertex; each anatomical part's vertex shader
/// interprets the two components differently (see JellyfishMeshBuilder).
struct PartVertex {
    var p0: SIMD4<Float>
    var p1: SIMD4<Float> = .zero
}

/// CPU-side mesh before upload.
struct MeshData {
    var vertices: [PartVertex] = []
    var indices: [UInt32] = []

    /// Appends a (rows+1)×(cols+1) vertex grid's triangle indices.
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
