import simd

/// Exhibit lighting, fixed in world space so that orbiting the specimen
/// reveals how light travels through its tissue.
struct LightingRig {
    /// Soft surface light from above (also drives Snell's window and light shafts).
    var keyDirection = simd_normalize(SIMD3<Float>(0.25, 1.0, 0.15))
    var keyColor: SIMD3<Float> = [0.75, 0.90, 1.00]
    var keyIntensity: Float = 1.15

    /// Cool, dim bounce light from below and behind.
    var fillDirection = simd_normalize(SIMD3<Float>(-0.8, -0.35, -0.5))
    var fillColor: SIMD3<Float> = [0.22, 0.35, 0.90]
    var fillIntensity: Float = 0.5

    /// Hemispherical ambient light from the surrounding water column.
    var ambientTop: SIMD3<Float> = [0.06, 0.12, 0.18]
    var ambientBottom: SIMD3<Float> = [0.01, 0.02, 0.045]

    // Post-processing
    var exposure: Float = 1.0
    var bloomStrength: Float = 0.5
    var vignette: Float = 0.45
}
