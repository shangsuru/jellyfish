import simd

/// Swimming rhythm and water motion. The actual deformation is evaluated
/// on the GPU (see `pulseAt`, `bellSurface`, `tentacleCenter`); this type
/// owns the clock and the tunable parameters.
struct SwimAnimation {
    /// Seconds per bell pulse.
    var pulsePeriod: Float = 3.8
    /// Scales how strongly the bell contracts (0 = still).
    var contraction: Float = 1.0
    /// Scales the free sway of arms and tentacles.
    var sway: Float = 1.0
    /// Delay (seconds per body unit) for motion to travel down arms and tentacles.
    var trailingLag: Float = 0.32
    /// Strength of the slowly turning water current.
    var currentStrength: Float = 0.22

    private(set) var time: Float = 0

    mutating func advance(by dt: Float) {
        time += dt
    }

    /// A gentle current whose direction and strength wander over minutes.
    var current: SIMD3<Float> {
        let angle = time * 0.045
        let strength = currentStrength * (0.7 + 0.3 * sin(time * 0.11))
        return SIMD3(cos(angle), 0.08 * sin(time * 0.07), sin(angle)) * strength
    }

    var uniforms: SIMD4<Float> {
        SIMD4(pulsePeriod, contraction, sway, trailingLag)
    }
}
