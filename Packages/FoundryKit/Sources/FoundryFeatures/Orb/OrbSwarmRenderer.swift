import Metal
import simd

/// Рендер роя «Восход» в две стадии: частицы в линейный буфер, затем семейное
/// сведение с гаммой на выход.
///
/// Порядок стадий несущий, а не косметический. Частицы рисуются непрозрачными
/// с тестом глубины — только так в пикселе оказывается ровно одна частица.
/// Включить блендинг значило бы сложить цвета двух семей, а их середина —
/// розовый ~300°, вычеркнутый из палитры.
public final class OrbSwarmRenderer {

    // Раскладка должна совпадать с OrbUniforms в OrbSwarm.metal.
    // float2 выравнивается по 8 байт, поэтому res встаёт на смещение 8.
    struct OrbUniforms {
        var time: Float = 0
        var count: Float = 0
        var res: SIMD2<Float> = .zero
        var zoom: Float = 0
        var pt: Float = 0
        var taper: Float = 0
    }

    struct ResolveUniforms {
        var time: Float = 0
        var ss: Int32 = 1
    }

    public enum SetupError: Error, CustomStringConvertible {
        case noLibrary(String)
        case noFunction(String)

        public var description: String {
            switch self {
            case .noLibrary(let m):  return "не собралась библиотека шейдеров: \(m)"
            case .noFunction(let n): return "в библиотеке нет функции \(n)"
            }
        }
    }

    public let device: MTLDevice
    public private(set) var config: OrbSwarmConfig

    private let queue: MTLCommandQueue
    private let orbPipeline: MTLRenderPipelineState
    private let postPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    private var colorTexture: MTLTexture!
    private var depthTexture: MTLTexture!

    public init(device: MTLDevice, config: OrbSwarmConfig, outputFormat: MTLPixelFormat) throws {
        self.device = device
        self.config = config

        guard let queue = device.makeCommandQueue() else {
            throw SetupError.noLibrary("нет очереди команд")
        }
        self.queue = queue

        let library = try Self.makeLibrary(device: device)

        func fn(_ name: String) throws -> MTLFunction {
            guard let f = library.makeFunction(name: name) else { throw SetupError.noFunction(name) }
            return f
        }

        let orbDesc = MTLRenderPipelineDescriptor()
        orbDesc.vertexFunction = try fn("orbVertex")
        orbDesc.fragmentFunction = try fn("orbFragment")
        // Линейная цель: частицы непрозрачные, так что копится тут не яркость,
        // а просто линейный цвет — гамма ждёт в пост-пассе.
        orbDesc.colorAttachments[0].pixelFormat = .rgba16Float
        // Блендинг НЕ включаем: он и делал розовое.
        orbDesc.colorAttachments[0].isBlendingEnabled = false
        orbDesc.depthAttachmentPixelFormat = .depth16Unorm
        orbPipeline = try device.makeRenderPipelineState(descriptor: orbDesc)

        let postDesc = MTLRenderPipelineDescriptor()
        postDesc.vertexFunction = try fn("postVertex")
        postDesc.fragmentFunction = try fn("postFragment")
        postDesc.colorAttachments[0].pixelFormat = outputFormat
        postPipeline = try device.makeRenderPipelineState(descriptor: postDesc)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        guard let ds = device.makeDepthStencilState(descriptor: depthDesc) else {
            throw SetupError.noLibrary("нет состояния глубины")
        }
        depthState = ds

        allocateTextures()
    }

    /// Библиотека шейдеров. Сначала готовый metallib — его собирает Xcode, если
    /// пакет едет внутри приложения. Под `swift build` его нет: SwiftPM файлы
    /// `.metal` не компилирует, а кладёт в бандл исходником (он так и говорит —
    /// «unhandled»). Тогда собираем из исходника в рантайме: это единственный
    /// путь, работающий в обоих случаях. Цена разовая, при старте.
    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let lib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            return lib
        }
        guard let url = Bundle.module.url(forResource: "OrbSwarm", withExtension: "metal") else {
            throw SetupError.noLibrary("в бандле нет ни default.metallib, ни OrbSwarm.metal")
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SetupError.noLibrary("не читается OrbSwarm.metal: \(error)")
        }
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw SetupError.noLibrary("не компилируется OrbSwarm.metal: \(error)")
        }
    }

    public func update(config newConfig: OrbSwarmConfig) {
        guard newConfig.buffer != config.buffer || newConfig.count != config.count
                || newConfig.pointSize != config.pointSize else {
            config = newConfig
            return
        }
        let needsRealloc = newConfig.buffer != config.buffer
        config = newConfig
        if needsRealloc { allocateTextures() }
    }

    private func allocateTextures() {
        let side = config.buffer

        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: side, height: side, mipmapped: false)
        colorDesc.usage = [.renderTarget, .shaderRead]
        colorDesc.storageMode = .private
        colorTexture = device.makeTexture(descriptor: colorDesc)

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth16Unorm, width: side, height: side, mipmapped: false)
        depthDesc.usage = .renderTarget
        depthDesc.storageMode = .private
        depthTexture = device.makeTexture(descriptor: depthDesc)
    }

    /// Кодирует оба прохода. Вызывающий сам коммитит буфер — так замер может
    /// повесить обработчик, а окно презентует drawable.
    public func encode(into commandBuffer: MTLCommandBuffer,
                       output: MTLTexture,
                       time: Float) {
        // 1. частицы — непрозрачными, с тестом глубины, в линейный буфер
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colorTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        // Альфа 0.5 метит фон: сведение отличает по ней «пусто» от семьи частицы.
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.00021, green: 0.00033, blue: 0.00160, alpha: 0.5)
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1.0

        guard let orbEnc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = OrbUniforms(
            time: time,
            count: Float(config.count),
            res: SIMD2<Float>(Float(config.buffer), Float(config.buffer)),
            zoom: OrbSwarmConfig.zoom,
            pt: config.pointSize,
            taper: OrbSwarmConfig.taper)
        orbEnc.setRenderPipelineState(orbPipeline)
        orbEnc.setDepthStencilState(depthState)
        orbEnc.setVertexBytes(&u, length: MemoryLayout<OrbUniforms>.stride, index: 0)
        // Атрибутов нет: позиции считаются из vertex_id прямо в шейдере.
        orbEnc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: config.count)
        orbEnc.endEncoding()

        // 2. семейное сведение + гамма на выход
        let postPass = MTLRenderPassDescriptor()
        postPass.colorAttachments[0].texture = output
        postPass.colorAttachments[0].loadAction = .dontCare
        postPass.colorAttachments[0].storeAction = .store

        guard let postEnc = commandBuffer.makeRenderCommandEncoder(descriptor: postPass) else { return }
        var r = ResolveUniforms(time: time, ss: Int32(config.supersample))
        postEnc.setRenderPipelineState(postPipeline)
        postEnc.setFragmentBytes(&r, length: MemoryLayout<ResolveUniforms>.stride, index: 0)
        postEnc.setFragmentTexture(colorTexture, index: 0)
        postEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        postEnc.endEncoding()
    }

    public func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }
}
