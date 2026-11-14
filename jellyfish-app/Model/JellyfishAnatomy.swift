import simd

/// Anatomical proportions of the specimen — a scyphozoan medusa with a
/// scalloped bell, four horseshoe gonads, a four-lobed manubrium, four
/// frilled oral arms and two rings of marginal tentacles.
///
/// Dimensions are in body units (bell radius ≈ 1). Values that shape the
/// geometry on the GPU are packed into `AnatomyUniforms`; counts and
/// resolutions drive `JellyfishMeshBuilder`.
struct JellyfishAnatomy {
    // Bell (umbrella)
    var bellRadius: Float = 1.0
    var bellHeight: Float = 0.78
    /// Arc swept by the bell profile; slightly over 90° curls the margin inward.
    var bellSweep: Float = 1.74
    var lappetCount = 16              // must be even
    var lappetDepth: Float = 0.045
    var apexThickness: Float = 0.17
    var marginThickness: Float = 0.012
    var bellRadialSegments = 80
    var bellAngularSegments = 256

    // Gonads (interradial horseshoes beneath the subumbrella)
    var gonadCount = 4
    var gonadRingRadius: Float = 0.30   // in bell profile units
    var gonadArcRadius: Float = 0.13
    var gonadTubeRadius: Float = 0.035
    var gonadFrill: Float = 0.35

    // Manubrium (central stalk carrying the mouth)
    var manubriumLength: Float = 0.30
    var manubriumRadius: Float = 0.085

    // Oral arms
    var oralArmCount = 4
    var oralArmLength: Float = 2.7
    var oralArmWidth: Float = 0.22
    var oralArmTwist: Float = 2.4
    var oralArmFrill: Float = 0.05
    var oralArmLengthSegments = 260
    var oralArmWidthSegments = 28

    // Marginal tentacles
    var longTentacleCount = 24
    var longTentacleLength: ClosedRange<Float> = 3.0...5.2
    var longTentacleRadius: Float = 0.0065
    var fringeTentacleCount = 96
    var fringeTentacleLength: ClosedRange<Float> = 0.18...0.55
    var fringeTentacleRadius: Float = 0.0035
    var tentacleRootU: Float = 0.985
    var tentacleTipTaper: Float = 0.3
    var tentacleBeadFrequency: Float = 55
    var tentacleBeadStrength: Float = 0.35
    var longTentacleSegments = 180
    var fringeTentacleSegments = 20

    var uniforms: AnatomyUniforms {
        AnatomyUniforms(
            bell: SIMD4(bellRadius, bellHeight, bellSweep, lappetDepth),
            bell2: SIMD4(Float(lappetCount), apexThickness, marginThickness, tentacleRootU),
            gonad: SIMD4(gonadRingRadius, gonadArcRadius, gonadTubeRadius, gonadFrill),
            oralArm: SIMD4(oralArmLength, oralArmWidth, oralArmTwist, oralArmFrill),
            tentacle: SIMD4(tentacleTipTaper, tentacleBeadFrequency, tentacleBeadStrength, 0),
            manubrium: SIMD4(manubriumLength, manubriumRadius, Float(oralArmCount), Float(gonadCount))
        )
    }
}
