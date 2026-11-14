import Foundation
import simd

/// Free-orbit trackball camera around the specimen.
///
/// Orientation is a quaternion, so the camera can travel over the top
/// and underneath without gimbal lock. Gestures feed rotation, zoom and
/// roll; `update(dt:)` applies inertia, smoothing and the reset animation.
final class OrbitCamera {
    let fieldOfView: Float = 38 * .pi / 180
    let nearPlane: Float = 0.02
    let farPlane: Float = 120

    // Default exhibit view: slightly above, looking gently down at the bell.
    let defaultOrientation = simd_quatf(angle: -0.2, axis: [1, 0, 0])
    let defaultDistance: Float = 9.5
    let maxDistance: Float = 16
    /// Closest approach from the side; larger above and below (see `minimumDistance`).
    let closestDistance: Float = 2.2

    /// Orbit pivot height when zoomed out (whole animal) and zoomed in (bell & arms).
    private let farPivotY: Float = -1.7
    private let nearPivotY: Float = -0.45

    private(set) var orientation: simd_quatf
    private(set) var distance: Float
    private var targetDistance: Float
    private var zoomStartDistance: Float = 0
    private var angularVelocity: SIMD2<Float> = .zero
    private var reset: ResetAnimation?

    /// Radians of rotation per point of finger travel.
    private let rotationSensitivity: Float = 0.008

    private struct ResetAnimation {
        var fromOrientation: simd_quatf
        var fromDistance: Float
        var progress: Float = 0
        let duration: Float = 1.4
    }

    init() {
        orientation = defaultOrientation
        distance = defaultDistance
        targetDistance = defaultDistance
    }

    // MARK: Gestures

    /// Trackball rotation from a finger drag (in points).
    func rotate(byPoints delta: SIMD2<Float>) {
        reset = nil
        angularVelocity = .zero
        applyRotation(delta * rotationSensitivity)
    }

    /// Continue spinning after the finger lifts, decaying naturally.
    func fling(velocity: SIMD2<Float>) {
        guard simd_length(velocity) > 60 else { return }
        angularVelocity = velocity * rotationSensitivity * 0.6
    }

    func beginZoom() {
        reset = nil
        zoomStartDistance = targetDistance
    }

    func zoom(scale: Float) {
        guard scale > 0 else { return }
        targetDistance = min(max(zoomStartDistance / scale, minimumDistance), maxDistance)
    }

    /// Roll around the viewing axis from a two-finger twist.
    func roll(by angle: Float) {
        reset = nil
        orientation = simd_normalize(orientation * simd_quatf(angle: angle, axis: [0, 0, 1]))
    }

    /// Smoothly returns to the default exhibit view.
    func resetView() {
        angularVelocity = .zero
        reset = ResetAnimation(fromOrientation: orientation, fromDistance: distance)
    }

    // MARK: Per-frame update

    func update(dt: Float) {
        if var anim = reset {
            anim.progress = min(anim.progress + dt / anim.duration, 1)
            let t = anim.progress
            let eased = t * t * t * (t * (t * 6 - 15) + 10)   // smootherstep
            orientation = simd_slerp(anim.fromOrientation, defaultOrientation, eased)
            distance = anim.fromDistance + (defaultDistance - anim.fromDistance) * eased
            targetDistance = distance
            reset = anim.progress >= 1 ? nil : anim
            return
        }

        if simd_length(angularVelocity) > 0.001 {
            applyRotation(angularVelocity * dt)
            angularVelocity *= exp(-3.0 * dt)
        } else {
            angularVelocity = .zero
        }

        // Keep a comfortable distance when orbiting above or below the animal.
        targetDistance = max(targetDistance, minimumDistance)
        distance += (targetDistance - distance) * (1 - exp(-12 * dt))
    }

    // MARK: Derived values

    var target: SIMD3<Float> {
        let t = smoothstep(closestDistance, defaultDistance, distance)
        return [0, nearPivotY + (farPivotY - nearPivotY) * t, 0]
    }

    var position: SIMD3<Float> {
        target + orientation.act([0, 0, distance])
    }

    var viewMatrix: simd_float4x4 {
        let world = simd_float4x4.translation(position) * simd_float4x4(orientation)
        return world.inverse
    }

    func projectionMatrix(aspect: Float) -> simd_float4x4 {
        .perspective(fovY: fieldOfView, aspect: aspect, near: nearPlane, far: farPlane)
    }

    /// Minimum orbit distance for the current direction: from directly
    /// above or below, the bell and trailing arms extend toward the camera.
    private var minimumDistance: Float {
        let dir = orientation.act([0, 0, 1])
        let below = max(0, -dir.y), above = max(0, dir.y)
        return closestDistance + 2.8 * below * below + 1.5 * above * above
    }

    private func applyRotation(_ angles: SIMD2<Float>) {
        // Rotations are applied in the camera's local frame, which makes the
        // drag behave like a free trackball in every orientation.
        let yaw = simd_quatf(angle: -angles.x, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: -angles.y, axis: [1, 0, 0])
        orientation = simd_normalize(orientation * yaw * pitch)
    }

    private func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
