import simd

/// 展示用の照明。ワールド空間に固定されているため、標本の周りを回ると
/// 光が組織をどう通り抜けるかが見えてくる。
struct LightingRig {
    /// 上方からの柔らかな水面光（スネルの窓と光の筋にも使われる）。
    var keyDirection = simd_normalize(SIMD3<Float>(0.25, 1.0, 0.15))
    var keyColor: SIMD3<Float> = [0.75, 0.90, 1.00]
    var keyIntensity: Float = 1.15

    /// 下方と背後からの、冷たく弱い反射光。
    var fillDirection = simd_normalize(SIMD3<Float>(-0.8, -0.35, -0.5))
    var fillColor: SIMD3<Float> = [0.22, 0.35, 0.90]
    var fillIntensity: Float = 0.5

    /// 周囲の水柱からの半球状の環境光。
    var ambientTop: SIMD3<Float> = [0.06, 0.12, 0.18]
    var ambientBottom: SIMD3<Float> = [0.01, 0.02, 0.045]

    // ポストプロセス
    var exposure: Float = 1.0
    var bloomStrength: Float = 0.5
    var vignette: Float = 0.45
}
