import simd

/// 標本の解剖学的なプロポーション。波形の傘、4つの馬蹄形の生殖腺、
/// 4葉の口柄、ひだのある4本の口腕、2列の縁触手を持つ
/// 鉢虫綱のクラゲ。
///
/// 寸法は体長単位（傘の半径 ≈ 1）。GPU 上で形状を決める値は
/// `AnatomyUniforms` にまとめられ、数と解像度は
/// `JellyfishMeshBuilder` が使う。
struct JellyfishAnatomy {
    // 傘
    var bellRadius: Float = 1.0
    var bellHeight: Float = 0.78
    /// 傘の断面が描く弧の角度。90°をわずかに超えると傘縁が内側に巻き込む。
    var bellSweep: Float = 1.74
    var lappetCount = 16              // 偶数であること
    var lappetDepth: Float = 0.045
    var apexThickness: Float = 0.17
    var marginThickness: Float = 0.012
    var bellRadialSegments = 80
    var bellAngularSegments = 256

    // 生殖腺（下傘面の下にある間輻位の馬蹄形）
    var gonadCount = 4
    var gonadRingRadius: Float = 0.30   // 傘の断面座標の単位
    var gonadArcRadius: Float = 0.13
    var gonadTubeRadius: Float = 0.035
    var gonadFrill: Float = 0.35

    // 口柄（口を持つ中央の柄）
    var manubriumLength: Float = 0.30
    var manubriumRadius: Float = 0.085

    // 口腕
    var oralArmCount = 4
    var oralArmLength: Float = 2.7
    var oralArmWidth: Float = 0.22
    var oralArmTwist: Float = 2.4
    var oralArmFrill: Float = 0.05
    var oralArmLengthSegments = 260
    var oralArmWidthSegments = 28

    // 縁触手
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
