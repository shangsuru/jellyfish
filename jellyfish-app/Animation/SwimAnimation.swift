import simd

/// 遊泳リズムと水の動き。実際の変形は GPU 上で評価され
/// （`pulseAt`、`bellSurface`、`tentacleCenter` を参照）、この型は
/// 時間と調整可能なパラメータを管理する。
struct SwimAnimation {
    /// 傘の拍動1回あたりの秒数。
    var pulsePeriod: Float = 3.8
    /// 傘の収縮の強さの倍率（0 = 静止）。
    var contraction: Float = 1.0
    /// 口腕と触手の自由な揺れの倍率。
    var sway: Float = 1.0
    /// 動きが口腕と触手を伝わって下がるまでの遅延（体長単位あたりの秒数）。
    var trailingLag: Float = 0.32
    /// ゆっくり向きを変える水流の強さ。
    var currentStrength: Float = 0.22

    private(set) var time: Float = 0

    mutating func advance(by dt: Float) {
        time += dt
    }

    /// 数分かけて向きと強さが移ろう穏やかな水流。
    var current: SIMD3<Float> {
        let angle = time * 0.045
        let strength = currentStrength * (0.7 + 0.3 * sin(time * 0.11))
        return SIMD3(cos(angle), 0.08 * sin(time * 0.07), sin(angle)) * strength
    }

    var uniforms: SIMD4<Float> {
        SIMD4(pulsePeriod, contraction, sway, trailingLag)
    }
}
