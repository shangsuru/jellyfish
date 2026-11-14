import MetalKit
import SwiftUI

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// Hosts the Metal-rendered jellyfish inside SwiftUI. Touch handling lives
/// in SwiftUI (see `ContentView`); this view only draws.
struct JellyfishMetalView: PlatformViewRepresentable {
    let camera: OrbitCamera

    final class Coordinator {
        var renderer: JellyfishRenderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView { makeView(context: context) }
    func updateNSView(_ view: MTKView, context: Context) {}
    #else
    func makeUIView(context: Context) -> MTKView {
        let view = makeView(context: context)
        view.isUserInteractionEnabled = false   // let SwiftUI gestures receive touches
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {}
    #endif

    private func makeView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        let renderer = JellyfishRenderer(view: view, camera: camera)
        context.coordinator.renderer = renderer
        view.delegate = renderer
        return view
    }
}
