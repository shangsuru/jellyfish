import MetalKit
import QuartzCore
import simd

/// クラゲ展示用のリアルタイム Metal レンダラ。
///
/// フレームの構成:
///  1. シーンパス（HDR、rgba16Float）: 水中の背景 → 浮遊粒子 →
///     半透明の解剖構造を、乗算済みアルファで合成する。
///  2. ブルーム: 明部を抽出して¼解像度に縮小し、分離可能なぼかしを2回かける。
///  3. ドローアブルへの合成: ブルーム、フィルム調トーンマッピング、ビネット、ディザ。
final class JellyfishRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let camera: OrbitCamera

    /// 注意: メッシュの解像度と数は初期化時に確定する。プロポーションはリアルタイムに反映される。
    var anatomy: JellyfishAnatomy
    var materials = JellyfishMaterials()
    var lighting = LightingRig()
    var animation = SwimAnimation()

    private struct GPUMesh {
        let vertexBuffer: MTLBuffer
        let indexBuffer: MTLBuffer
        let indexCount: Int
    }

    private struct Pipelines {
        let background: MTLRenderPipelineState
        let particles: MTLRenderPipelineState
        let bell: MTLRenderPipelineState
        let gonads: MTLRenderPipelineState
        let manubrium: MTLRenderPipelineState
        let oralArms: MTLRenderPipelineState
        let tentacles: MTLRenderPipelineState
        let bloomPrefilter: MTLRenderPipelineState
        let bloomBlur: MTLRenderPipelineState
        let composite: MTLRenderPipelineState
    }

    private struct Meshes {
        let bell: GPUMesh
        let gonads: GPUMesh
        let manubrium: GPUMesh
        let oralArms: GPUMesh
        let tentacles: GPUMesh
        let particles: GPUMesh
    }

    private enum Blend { case opaque, premultiplied, additive }

    private let pipelines: Pipelines
    private let meshes: Meshes
    private static let hdrFormat: MTLPixelFormat = .rgba16Float

    private var sceneTexture: MTLTexture?
    private var bloomA: MTLTexture?
    private var bloomB: MTLTexture?

    private var lastTimestamp: CFTimeInterval?
    private static let particleFieldExtent: Float = 22

    init?(view: MTKView, camera: OrbitCamera) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.queue = queue
        self.camera = camera

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 120
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        do {
            func make(_ vertex: String, _ fragment: String,
                      format: MTLPixelFormat, blend: Blend) throws -> MTLRenderPipelineState {
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = library.makeFunction(name: vertex)
                desc.fragmentFunction = library.makeFunction(name: fragment)
                let color = desc.colorAttachments[0]!
                color.pixelFormat = format
                switch blend {
                case .opaque:
                    color.isBlendingEnabled = false
                case .premultiplied:
                    color.isBlendingEnabled = true
                    color.sourceRGBBlendFactor = .one
                    color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    color.sourceAlphaBlendFactor = .one
                    color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                case .additive:
                    color.isBlendingEnabled = true
                    color.sourceRGBBlendFactor = .one
                    color.destinationRGBBlendFactor = .one
                    color.sourceAlphaBlendFactor = .zero
                    color.destinationAlphaBlendFactor = .one
                }
                return try device.makeRenderPipelineState(descriptor: desc)
            }

            pipelines = Pipelines(
                background: try make("backgroundVertex", "backgroundFragment", format: Self.hdrFormat, blend: .opaque),
                particles: try make("particleVertex", "particleFragment", format: Self.hdrFormat, blend: .additive),
                bell: try make("bellVertex", "bellFragment", format: Self.hdrFormat, blend: .premultiplied),
                gonads: try make("gonadVertex", "gonadFragment", format: Self.hdrFormat, blend: .premultiplied),
                manubrium: try make("manubriumVertex", "manubriumFragment", format: Self.hdrFormat, blend: .premultiplied),
                oralArms: try make("oralArmVertex", "oralArmFragment", format: Self.hdrFormat, blend: .premultiplied),
                tentacles: try make("tentacleVertex", "tentacleFragment", format: Self.hdrFormat, blend: .premultiplied),
                bloomPrefilter: try make("fullscreenVertex", "bloomPrefilter", format: Self.hdrFormat, blend: .opaque),
                bloomBlur: try make("fullscreenVertex", "bloomBlur", format: Self.hdrFormat, blend: .opaque),
                composite: try make("fullscreenVertex", "compositeFragment", format: view.colorPixelFormat, blend: .opaque)
            )
        } catch {
            print("Jellyfish pipeline creation failed: \(error)")
            return nil
        }

        let anatomy = JellyfishAnatomy()
        self.anatomy = anatomy
        var rng = SeededRandom(seed: 0x4A45_4C4C_59)
        func upload(_ data: MeshData) -> GPUMesh? {
            guard let vb = device.makeBuffer(bytes: data.vertices,
                                             length: MemoryLayout<PartVertex>.stride * data.vertices.count),
                  let ib = device.makeBuffer(bytes: data.indices,
                                             length: MemoryLayout<UInt32>.stride * data.indices.count)
            else { return nil }
            return GPUMesh(vertexBuffer: vb, indexBuffer: ib, indexCount: data.indices.count)
        }
        guard let bell = upload(JellyfishMeshBuilder.bell(anatomy)),
              let gonads = upload(JellyfishMeshBuilder.gonads(anatomy)),
              let manubrium = upload(JellyfishMeshBuilder.manubrium(anatomy)),
              let arms = upload(JellyfishMeshBuilder.oralArms(anatomy, rng: &rng)),
              let tentacles = upload(JellyfishMeshBuilder.tentacles(anatomy, rng: &rng)),
              let particles = upload(JellyfishMeshBuilder.particles(count: 900, extent: Self.particleFieldExtent, rng: &rng))
        else { return nil }
        meshes = Meshes(bell: bell, gonads: gonads, manubrium: manubrium,
                        oralArms: arms, tentacles: tentacles, particles: particles)

        super.init()
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        sceneTexture = nil   // 新しいサイズで必要になったときに再作成する
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(now - (lastTimestamp ?? now), 1.0 / 20.0))
        lastTimestamp = now
        animation.advance(by: dt)
        camera.update(dt: dt)

        let width = Int(view.drawableSize.width), height = Int(view.drawableSize.height)
        guard width > 0, height > 0,
              ensureTargets(width: width, height: height),
              let scene = sceneTexture, let bloomA, let bloomB,
              let commandBuffer = queue.makeCommandBuffer() else { return }

        var frame = makeFrameUniforms(width: width, height: height)
        var anatomyUniforms = anatomy.uniforms

        encodeScene(commandBuffer, target: scene, frame: &frame, anatomy: &anatomyUniforms)
        encodeBloom(commandBuffer, scene: scene, bloomA: bloomA, bloomB: bloomB)

        guard let passDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            commandBuffer.commit()
            return
        }
        encoder.label = "Composite"
        var params = SIMD4<Float>(lighting.bloomStrength, lighting.exposure, animation.time, lighting.vignette)
        encoder.setRenderPipelineState(pipelines.composite)
        encoder.setFragmentTexture(scene, index: 0)
        encoder.setFragmentTexture(bloomA, index: 1)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: パス

    private func encodeScene(_ commandBuffer: MTLCommandBuffer, target: MTLTexture,
                             frame: inout FrameUniforms, anatomy: inout AnatomyUniforms) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare   // 背景がすべてのピクセルを覆う
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Scene"
        encoder.setCullMode(.none)

        let frameSize = MemoryLayout<FrameUniforms>.stride
        let anatomySize = MemoryLayout<AnatomyUniforms>.stride
        encoder.setVertexBytes(&frame, length: frameSize, index: 1)
        encoder.setVertexBytes(&anatomy, length: anatomySize, index: 2)
        encoder.setFragmentBytes(&frame, length: frameSize, index: 0)
        encoder.setFragmentBytes(&anatomy, length: anatomySize, index: 2)

        // 水中の背景
        encoder.setRenderPipelineState(pipelines.background)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // カメラに追従する領域内の浮遊粒子
        var field = SIMD4<Float>(camera.position, Self.particleFieldExtent)
        encoder.setRenderPipelineState(pipelines.particles)
        encoder.setVertexBuffer(meshes.particles.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&field, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
        drawIndexed(meshes.particles, encoder: encoder)
        encoder.setVertexBytes(&anatomy, length: anatomySize, index: 2)

        // 半透明の解剖構造をおおよそ奥から手前へ描く。不透明度が低いため、
        // 下から見ているか上から見ているかに基づく大まかな順序で十分。
        let bellLayers = { self.draw(self.meshes.bell, self.pipelines.bell, self.materials.bell, instances: 2, encoder) }
        let hanging = {
            self.draw(self.meshes.tentacles, self.pipelines.tentacles, self.materials.tentacles, encoder)
            self.draw(self.meshes.oralArms, self.pipelines.oralArms, self.materials.oralArms, encoder)
            self.draw(self.meshes.manubrium, self.pipelines.manubrium, self.materials.manubrium, encoder)
        }
        let gonads = { self.draw(self.meshes.gonads, self.pipelines.gonads, self.materials.gonads, encoder) }

        if frame.cameraPos.y < -0.6 {
            bellLayers(); gonads(); hanging()
        } else {
            hanging(); gonads(); bellLayers()
        }
        encoder.endEncoding()
    }

    private func encodeBloom(_ commandBuffer: MTLCommandBuffer, scene: MTLTexture,
                             bloomA: MTLTexture, bloomB: MTLTexture) {
        fullscreenPass(commandBuffer, target: bloomA, pipeline: pipelines.bloomPrefilter) { encoder in
            encoder.setFragmentTexture(scene, index: 0)
        }
        let texel = SIMD2<Float>(1 / Float(bloomA.width), 1 / Float(bloomA.height))
        for radius: Float in [1.0, 2.2] {
            blur(commandBuffer, from: bloomA, to: bloomB, step: [texel.x * radius, 0])
            blur(commandBuffer, from: bloomB, to: bloomA, step: [0, texel.y * radius])
        }
    }

    private func blur(_ commandBuffer: MTLCommandBuffer, from source: MTLTexture,
                      to target: MTLTexture, step: SIMD2<Float>) {
        fullscreenPass(commandBuffer, target: target, pipeline: pipelines.bloomBlur) { encoder in
            var s = step
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(&s, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        }
    }

    private func fullscreenPass(_ commandBuffer: MTLCommandBuffer, target: MTLTexture,
                                pipeline: MTLRenderPipelineState,
                                configure: (MTLRenderCommandEncoder) -> Void) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        configure(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func draw(_ mesh: GPUMesh, _ pipeline: MTLRenderPipelineState, _ material: TissueMaterial,
                      instances: Int = 1, _ encoder: MTLRenderCommandEncoder) {
        var uniforms = material.uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MaterialUniforms>.stride, index: 1)
        drawIndexed(mesh, instances: instances, encoder: encoder)
    }

    private func drawIndexed(_ mesh: GPUMesh, instances: Int = 1, encoder: MTLRenderCommandEncoder) {
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount, indexType: .uint32,
                                      indexBuffer: mesh.indexBuffer, indexBufferOffset: 0,
                                      instanceCount: instances)
    }

    // MARK: ヘルパー

    private func makeFrameUniforms(width: Int, height: Int) -> FrameUniforms {
        let aspect = Float(width) / Float(height)
        let view = camera.viewMatrix
        let viewProj = camera.projectionMatrix(aspect: aspect) * view
        let pixelAngle = 2 * tan(camera.fieldOfView / 2) / Float(height)

        return FrameUniforms(
            viewProj: viewProj,
            view: view,
            invViewProj: viewProj.inverse,
            cameraPos: SIMD4(camera.position, animation.time),
            viewport: SIMD4(Float(width), Float(height), pixelAngle, camera.distance),
            keyLightDir: SIMD4(lighting.keyDirection, lighting.keyIntensity),
            keyLightColor: SIMD4(lighting.keyColor, 1),
            fillLightDir: SIMD4(lighting.fillDirection, lighting.fillIntensity),
            fillLightColor: SIMD4(lighting.fillColor, 1),
            ambientTop: SIMD4(lighting.ambientTop, 1),
            ambientBottom: SIMD4(lighting.ambientBottom, 1),
            anim: animation.uniforms,
            current: SIMD4(animation.current, 0)
        )
    }

    private func ensureTargets(width: Int, height: Int) -> Bool {
        if let scene = sceneTexture, scene.width == width, scene.height == height { return true }
        func make(_ w: Int, _ h: Int) -> MTLTexture? {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.hdrFormat, width: max(w, 1),
                                                                height: max(h, 1), mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            return device.makeTexture(descriptor: desc)
        }
        sceneTexture = make(width, height)
        bloomA = make(width / 4, height / 4)
        bloomB = make(width / 4, height / 4)
        return sceneTexture != nil && bloomA != nil && bloomB != nil
    }
}
