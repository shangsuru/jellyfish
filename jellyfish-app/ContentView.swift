import SwiftUI

/// The exhibit: a single jellyfish suspended in dark water.
///
/// - Drag: rotate freely in any direction (with inertia)
/// - Pinch: zoom
/// - Two-finger twist: roll
/// - Double-tap or the reset button: return to the default view
struct ContentView: View {
    @State private var camera = OrbitCamera()
    @State private var lastDrag: CGSize = .zero
    @State private var lastRoll: Angle = .zero
    @State private var isZooming = false
    @State private var showsReset = false

    var body: some View {
        JellyfishMetalView(camera: camera)
            .ignoresSafeArea()
            .contentShape(.rect)
            .gesture(rotateGesture)
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(rollGesture)
            .onTapGesture(count: 2, perform: resetView)
            .accessibilityElement()
            .accessibilityLabel("Jellyfish specimen")
            .accessibilityHint("Drag to rotate, pinch to zoom, double-tap to reset the view.")
            .overlay(alignment: .bottomTrailing) {
                if showsReset {
                    resetButton
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: showsReset)
            .background(.black)
            .hidesSystemChrome()
    }

    private var resetButton: some View {
        Button(action: resetView) {
            Image(systemName: "arrow.counterclockwise")
                .font(.body.weight(.medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass(.clear))
        .tint(.white.opacity(0.8))
        .accessibilityLabel("Reset view")
        .padding(20)
    }

    // MARK: Gestures

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let dx = value.translation.width - lastDrag.width
                let dy = value.translation.height - lastDrag.height
                lastDrag = value.translation
                // Ignore jumps when fingers are added or lifted mid-gesture.
                guard abs(dx) < 80, abs(dy) < 80 else { return }
                camera.rotate(byPoints: SIMD2(Float(dx), Float(dy)))
                showsReset = true
            }
            .onEnded { value in
                lastDrag = .zero
                camera.fling(velocity: SIMD2(Float(value.velocity.width), Float(value.velocity.height)))
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isZooming {
                    camera.beginZoom()
                    isZooming = true
                }
                camera.zoom(scale: Float(value.magnification))
                showsReset = true
            }
            .onEnded { _ in isZooming = false }
    }

    private var rollGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                let delta = value.rotation - lastRoll
                lastRoll = value.rotation
                camera.roll(by: Float(delta.radians))
                showsReset = true
            }
            .onEnded { _ in lastRoll = .zero }
    }

    private func resetView() {
        camera.resetView()
        showsReset = false
    }
}

private extension View {
    /// Immersive presentation: no status bar or home indicator competing with the specimen.
    func hidesSystemChrome() -> some View {
        #if os(iOS)
        return self
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
        #else
        return self
        #endif
    }
}

#Preview {
    ContentView()
}
