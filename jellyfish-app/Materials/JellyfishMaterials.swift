import simd

/// Translucent tissue description for one anatomical part.
/// Colours are linear HDR; opacities are kept low because jellyfish tissue
/// is ~95% water and mostly scatters rather than absorbs light.
struct TissueMaterial {
    var baseColor: SIMD3<Float>
    var baseOpacity: Float
    var rimColor: SIMD3<Float>
    var rimOpacity: Float
    var detailColor: SIMD3<Float>
    var detailStrength: Float
    var accentColor: SIMD3<Float>
    var accentStrength: Float
    var fresnelPower: Float
    var scatter: Float
    var specular: Float
    var transmission: Float

    var uniforms: MaterialUniforms {
        MaterialUniforms(
            baseColor: SIMD4(baseColor, baseOpacity),
            rimColor: SIMD4(rimColor, rimOpacity),
            detailColor: SIMD4(detailColor, detailStrength),
            accentColor: SIMD4(accentColor, accentStrength),
            params: SIMD4(fresnelPower, scatter, specular, transmission)
        )
    }
}

/// The specimen's palette: a glassy, faintly blue bell with a warm apex,
/// lilac gonads and pale pink-tipped oral arms.
struct JellyfishMaterials {
    var bell = TissueMaterial(
        baseColor: [0.55, 0.75, 0.90], baseOpacity: 0.028,
        rimColor: [0.55, 0.85, 1.00], rimOpacity: 0.32,
        detailColor: [0.95, 0.80, 0.90], detailStrength: 1.0,     // canals
        accentColor: [1.00, 0.78, 0.70], accentStrength: 0.55,    // warm apex
        fresnelPower: 2.6, scatter: 0.9, specular: 0.55, transmission: 0.7)

    var gonads = TissueMaterial(
        baseColor: [0.95, 0.42, 0.72], baseOpacity: 0.2,
        rimColor: [1.00, 0.72, 0.90], rimOpacity: 0.45,
        detailColor: [1.00, 0.88, 0.95], detailStrength: 1.0,
        accentColor: [0.75, 0.50, 1.00], accentStrength: 0.4,
        fresnelPower: 2.0, scatter: 1.0, specular: 0.3, transmission: 0.6)

    var manubrium = TissueMaterial(
        baseColor: [0.90, 0.80, 0.88], baseOpacity: 0.03,
        rimColor: [0.85, 0.90, 1.00], rimOpacity: 0.22,
        detailColor: [1.0, 1.0, 1.0], detailStrength: 0,
        accentColor: [1.0, 1.0, 1.0], accentStrength: 0,
        fresnelPower: 2.2, scatter: 0.9, specular: 0.3, transmission: 0.5)

    var oralArms = TissueMaterial(
        baseColor: [0.82, 0.84, 0.95], baseOpacity: 0.03,
        rimColor: [0.80, 0.90, 1.00], rimOpacity: 0.28,
        detailColor: [1.00, 0.62, 0.78], detailStrength: 0.6,     // pink frilled margins
        accentColor: [0.95, 0.85, 0.80], accentStrength: 0.5,     // central canal
        fresnelPower: 2.2, scatter: 0.9, specular: 0.35, transmission: 0.6)

    var tentacles = TissueMaterial(
        baseColor: [0.95, 0.82, 0.80], baseOpacity: 0.3,
        rimColor: [0.85, 0.92, 1.00], rimOpacity: 0.35,
        detailColor: [1.00, 0.97, 0.92], detailStrength: 0.7,     // nematocyst batteries
        accentColor: [1.0, 1.0, 1.0], accentStrength: 0,
        fresnelPower: 2.0, scatter: 0.8, specular: 0.2, transmission: 0.5)
}
