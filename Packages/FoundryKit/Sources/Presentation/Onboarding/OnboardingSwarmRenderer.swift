import Metal
import simd

/// Рендер роя онбординга: частицы в линейный буфер (+ световые следы разлёта),
/// затем семейное сведение с гаммой на выход. Прямоугольный кадр окна установки,
/// в отличие от квадратного логотипа (`OrbSwarmRenderer`).
///
/// Отдельный рендерер, а не расширение принятого `OrbSwarmRenderer`: у логотипа
/// своя утверждённая раскладка, и «улучшать заодно» её нельзя.
///
/// Дублирование с `OrbSwarmRenderer` (структура init/encode, загрузка библиотеки,
/// выделение текстур) осознанное и оставлено намеренно. Общий рендер-кор свёл бы
/// две вещи, которые ОБЯЗАНЫ эволюционировать порознь (утверждённый логотип vs
/// онбординговый рой), в одну абстракцию — а преждевременное «DRY» здесь и есть
/// wrong abstraction, которая хуже дублирования: любая правка одного роя протекала
/// бы в другой и грозила утверждённой раскладке. Оба `encode` выровнены на пары
/// проходов (particle/resolve), так что при появлении настоящей общей потребности
/// слить можно будет байт-идентичный низ, не трогая uniform-математику.
final class OnboardingSwarmRenderer {

    /// Раскладка должна совпадать с SwarmUniforms в OnboardingSwarm.metal.
    /// float2 выравнивается по 8 байт — центр и resolution встают на кратные 8 смещения.
    struct SwarmUniforms {
        var time: Float = 0
        var count: Float = 0
        var resolution: SIMD2<Float> = .zero
        var zoom: Float = 0
        var pointSize: Float = 0
        var taper: Float = 0
        var aspect: Float = 1
        var center: SIMD2<Float> = .zero
        var fit: Float = 1
        var burst: Float = 0
        var mode: Int32 = 0
        var step: Float = 0.015
        var jitter: Float = 0
        var t0: Float = 0
    }

    struct ResolveUniforms {
        var time: Float = 0
        var supersample: Int32 = 1
    }

    /// = const SEGS в шейдере: вершин на частицу в режиме линий — SEGS*2.
    static let segments = 8

    enum SetupError: Error, CustomStringConvertible {
        case resourceMissing(String)
        case noFunction(String)
        var description: String {
            switch self {
            case .resourceMissing(let m): return "не собралась библиотека шейдеров: \(m)"
            case .noFunction(let n): return "в библиотеке нет функции \(n)"
            }
        }
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let particlePipeline: MTLRenderPipelineState
    private let resolvePipeline: MTLRenderPipelineState
    private let depthWriteState: MTLDepthStencilState
    private let depthReadOnlyState: MTLDepthStencilState

    private var colorTexture: MTLTexture!
    private var depthTexture: MTLTexture!
    private var bufferWidth = 0
    private var bufferHeight = 0

    init(device: MTLDevice, outputFormat: MTLPixelFormat) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw SetupError.resourceMissing("нет очереди команд")
        }
        self.queue = queue

        let library = try Self.makeLibrary(device: device)
        func loadFunction(_ name: String) throws -> MTLFunction {
            guard let function = library.makeFunction(name: name) else {
                throw SetupError.noFunction(name)
            }
            return function
        }

        let particleDesc = MTLRenderPipelineDescriptor()
        particleDesc.vertexFunction = try loadFunction("swarmVertex")
        particleDesc.fragmentFunction = try loadFunction("swarmFragment")
        particleDesc.colorAttachments[0].pixelFormat = .rgba16Float
        particleDesc.colorAttachments[0].isBlendingEnabled = false
        particleDesc.depthAttachmentPixelFormat = .depth16Unorm
        particlePipeline = try device.makeRenderPipelineState(descriptor: particleDesc)

        let resolveDesc = MTLRenderPipelineDescriptor()
        resolveDesc.vertexFunction = try loadFunction("swarmPostVertex")
        resolveDesc.fragmentFunction = try loadFunction("swarmPostFragment")
        resolveDesc.colorAttachments[0].pixelFormat = outputFormat
        resolvePipeline = try device.makeRenderPipelineState(descriptor: resolveDesc)

        // Точки пишут глубину (одна частица в пикселе); следы-линии только
        // тестируют её (depthMask false в прототипе) — линии не заслоняют точки.
        let writeDesc = MTLDepthStencilDescriptor()
        writeDesc.depthCompareFunction = .less
        writeDesc.isDepthWriteEnabled = true
        let noWriteDesc = MTLDepthStencilDescriptor()
        noWriteDesc.depthCompareFunction = .less
        noWriteDesc.isDepthWriteEnabled = false
        guard let writeState = device.makeDepthStencilState(descriptor: writeDesc),
            let noWriteState = device.makeDepthStencilState(descriptor: noWriteDesc)
        else {
            throw SetupError.resourceMissing("нет состояния глубины")
        }
        depthWriteState = writeState
        depthReadOnlyState = noWriteState
    }

    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let lib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            // default.metallib собран Xcode — в нём есть функции обоих роёв.
            if lib.makeFunction(name: "swarmVertex") != nil { return lib }
        }
        guard let url = Bundle.module.url(forResource: "OnboardingSwarm", withExtension: "metal") else {
            throw SetupError.resourceMissing(
                "в бандле нет ни default.metallib с ройем, ни OnboardingSwarm.metal")
        }
        let source: String
        do { source = try String(contentsOf: url, encoding: .utf8) } catch {
            throw SetupError.resourceMissing("не читается OnboardingSwarm.metal: \(error)")
        }
        do { return try device.makeLibrary(source: source, options: nil) } catch {
            throw SetupError.resourceMissing("не компилируется OnboardingSwarm.metal: \(error)")
        }
    }

    /// Перевыделить буферы под новый размер (в пикселях буфера).
    func resize(bufferWidth: Int, bufferHeight: Int) {
        guard bufferWidth != self.bufferWidth || bufferHeight != self.bufferHeight,
            bufferWidth > 0, bufferHeight > 0
        else { return }
        self.bufferWidth = bufferWidth
        self.bufferHeight = bufferHeight

        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: bufferWidth, height: bufferHeight, mipmapped: false)
        colorDesc.usage = [.renderTarget, .shaderRead]
        colorDesc.storageMode = .private
        colorTexture = device.makeTexture(descriptor: colorDesc)

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth16Unorm, width: bufferWidth, height: bufferHeight, mipmapped: false)
        depthDesc.usage = .renderTarget
        depthDesc.storageMode = .private
        depthTexture = device.makeTexture(descriptor: depthDesc)
    }

    func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    /// Кодирует оба прохода. `uniforms.mode`/`jitter` перекрываются внутри —
    /// вызывающий задаёт всё остальное. Следы рисуются только при `drawsTrails`.
    func encode(
        into commandBuffer: MTLCommandBuffer,
        output: MTLTexture,
        uniforms base: SwarmUniforms,
        supersample: Int,
        drawsTrails: Bool
    ) {
        guard let colorTexture, let depthTexture else { return }
        encodeParticlePass(
            into: commandBuffer, colorTexture: colorTexture, depthTexture: depthTexture,
            base: base, drawsTrails: drawsTrails)
        encodeResolvePass(
            into: commandBuffer, output: output, colorTexture: colorTexture,
            time: base.time, supersample: supersample)
    }

    /// Проход 1: частицы (пишут глубину) + следы разлёта (три блюр-прохода без
    /// записи глубины) — в линейный буфер `colorTexture`.
    private func encodeParticlePass(
        into commandBuffer: MTLCommandBuffer,
        colorTexture: MTLTexture,
        depthTexture: MTLTexture,
        base: SwarmUniforms,
        drawsTrails: Bool
    ) {
        let particleCount = Int(base.count)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colorTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        // Альфа 0.5 метит фон: сведение отличает по ней «пусто» от семьи.
        // RGB = BG_LIN #241E3B (сведение всё равно берёт фон из BG_LIN в шейдере;
        // держим в паре для корректного антиалиасинга кромок частиц о фон).
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.017764, green: 0.012983, blue: 0.043735, alpha: 0.5)
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1.0

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(particlePipeline)

        // точки
        encoder.setDepthStencilState(depthWriteState)
        var pointUniforms = base
        pointUniforms.mode = 0
        pointUniforms.jitter = 0
        encoder.setVertexBytes(&pointUniforms, length: MemoryLayout<SwarmUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)

        // следы разлёта: три прохода (основная линия + два блюр-хвоста),
        // без записи глубины — линии не заслоняют частицы
        if drawsTrails {
            encoder.setDepthStencilState(depthReadOnlyState)
            let lineVertexCount = particleCount * Self.segments * 2
            for jitter in [Float(0), 1.6, -1.6] {
                var lineUniforms = base
                lineUniforms.mode = 1
                lineUniforms.jitter = jitter
                encoder.setVertexBytes(&lineUniforms, length: MemoryLayout<SwarmUniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lineVertexCount)
            }
        }
        encoder.endEncoding()
    }

    /// Проход 2: семейное сведение линейного буфера + гамма — на выходную текстуру.
    private func encodeResolvePass(
        into commandBuffer: MTLCommandBuffer,
        output: MTLTexture,
        colorTexture: MTLTexture,
        time: Float,
        supersample: Int
    ) {
        let resolvePass = MTLRenderPassDescriptor()
        resolvePass.colorAttachments[0].texture = output
        resolvePass.colorAttachments[0].loadAction = .dontCare
        resolvePass.colorAttachments[0].storeAction = .store

        guard let resolveEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: resolvePass)
        else { return }
        var resolveUniforms = ResolveUniforms(time: time, supersample: Int32(supersample))
        resolveEncoder.setRenderPipelineState(resolvePipeline)
        resolveEncoder.setFragmentBytes(
            &resolveUniforms, length: MemoryLayout<ResolveUniforms>.stride, index: 0)
        resolveEncoder.setFragmentTexture(colorTexture, index: 0)
        resolveEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        resolveEncoder.endEncoding()
    }
}
