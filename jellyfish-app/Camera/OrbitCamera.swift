import Foundation
import simd

/// 標本の周囲を自由に周回するトラックボールカメラ。
///
/// 向きはクォータニオンで保持するため、ジンバルロックなしで
/// 真上や真下へも回り込める。ジェスチャーが回転・ズーム・ロールを入力し、
/// `update(dt:)` が慣性・スムージング・リセットアニメーションを適用する。
final class OrbitCamera {
    let fieldOfView: Float = 38 * .pi / 180
    let nearPlane: Float = 0.02
    let farPlane: Float = 120

    // デフォルトの展示視点: やや上から傘を緩やかに見下ろす。
    let defaultOrientation = simd_quatf(angle: -0.2, axis: [1, 0, 0])
    let defaultDistance: Float = 9.5
    let maxDistance: Float = 16
    /// 側面からの最接近距離。上下からはより大きくなる（`minimumDistance` を参照）。
    let closestDistance: Float = 2.2

    /// ズームアウト時（全身）とズームイン時（傘と口腕）の回転中心の高さ。
    private let farPivotY: Float = -1.7
    private let nearPivotY: Float = -0.45

    private(set) var orientation: simd_quatf
    private(set) var distance: Float
    private var targetDistance: Float
    private var zoomStartDistance: Float = 0
    private var angularVelocity: SIMD2<Float> = .zero
    private var reset: ResetAnimation?

    /// 指の移動1ポイントあたりの回転量（ラジアン）。
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

    // MARK: ジェスチャー

    /// 指のドラッグ（ポイント単位）によるトラックボール回転。
    func rotate(byPoints delta: SIMD2<Float>) {
        reset = nil
        angularVelocity = .zero
        applyRotation(delta * rotationSensitivity)
    }

    /// 指を離した後も回転を続け、自然に減衰させる。
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

    /// 2本指のひねりで視線軸まわりにロールする。
    func roll(by angle: Float) {
        reset = nil
        orientation = simd_normalize(orientation * simd_quatf(angle: angle, axis: [0, 0, 1]))
    }

    /// デフォルトの展示視点へ滑らかに戻る。
    func resetView() {
        angularVelocity = .zero
        reset = ResetAnimation(fromOrientation: orientation, fromDistance: distance)
    }

    // MARK: フレームごとの更新

    func update(dt: Float) {
        if var anim = reset {
            anim.progress = min(anim.progress + dt / anim.duration, 1)
            let t = anim.progress
            let eased = t * t * t * (t * (t * 6 - 15) + 10)   // スムーザーステップ
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

        // クラゲの上下を周回するときは快適な距離を保つ。
        targetDistance = max(targetDistance, minimumDistance)
        distance += (targetDistance - distance) * (1 - exp(-12 * dt))
    }

    // MARK: 派生値

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

    /// 現在の方向での最小周回距離: 真上や真下からは
    /// 傘や垂れ下がる口腕がカメラ側へ伸びてくるため。
    private var minimumDistance: Float {
        let dir = orientation.act([0, 0, 1])
        let below = max(0, -dir.y), above = max(0, dir.y)
        return closestDistance + 2.8 * below * below + 1.5 * above * above
    }

    private func applyRotation(_ angles: SIMD2<Float>) {
        // 回転はカメラのローカル座標系で適用するため、
        // どの向きでもドラッグが自由なトラックボールのように振る舞う。
        let yaw = simd_quatf(angle: -angles.x, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: -angles.y, axis: [1, 0, 0])
        orientation = simd_normalize(orientation * yaw * pitch)
    }

    private func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
