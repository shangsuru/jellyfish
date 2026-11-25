import MetalKit
import SwiftUI

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// Metal で描画したクラゲを SwiftUI 内に表示する。タッチ処理は
/// SwiftUI 側（`ContentView` を参照）にあり、このビューは描画のみを行う。
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
        view.isUserInteractionEnabled = false   // タッチを SwiftUI のジェスチャーに渡す
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
