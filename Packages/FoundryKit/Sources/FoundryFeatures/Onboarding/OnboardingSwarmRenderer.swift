import Metal
import simd

/// Рендер роя онбординга: частицы в линейный буфер (+ световые следы разлёта),
/// затем семейное сведение с гаммой на выход. Прямоугольный кадр окна установки,
/// в отличие от квадратного логотипа (`OrbSwarmRenderer`).
///
/// Отдельный рендерер, а не расширение принятого `OrbSwarmRenderer`: у логотипа
/// своя утверждённая раскладка, и «улучшать заодно» её нельзя.
final class OnboardingSwarmRenderer {

    /// Раскладка должна совпадать с SwarmUniforms в OnboardingSwarm.metal.
    /// float2 выравнивается по 8 байт — центр и res встают на кратные 8 смещения.
    struct SwarmUniforms {
        var time: Float = 0
        var count: Float = 0
        var res: SIMD2<Float> = .zero
        var zoom: Float = 0
        var pt: Float = 0
        var taper: Float = 0
        var aspect: Float = 1
        var center: SIMD2<Float> = .zero
        var fit: Float = 1
        var burst: Float = 0
        var mode: Int32 = 0
        var step: Float = 0.015
        var jit: Float = 0
        var t0: Float = 0
    }

    struct ResolveUniforms {
        var time: Float = 0
        var ss: Int32 = 1
    }

    /// = const SEGS в шейдере: вершин на частицу в режиме линий — SEGS*2.
    static let segs = 8

    enum SetupError: Error, CustomStringConvertible {
        case noLibrary(String)
        case noFunction(String)
        var description: String {
            switch self {
            case .noLibrary(let m): return "не собралась библиотека шейдеров: \(m)"
            case .noFunction(let n): return "в библиотеке нет функции \(n)"
            }
        }
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let orbPipeline: MTLRenderPipelineState
    private let postPipeline: MTLRenderPipelineState
    private let depthWrite: MTLDepthStencilState
    private let depthNoWrite: MTLDepthStencilState

    private var colorTexture: MTLTexture!
    private var depthTexture: MTLTexture!
    private var bufW = 0
    private var bufH = 0

    init(device: MTLDevice, outputFormat: MTLPixelFormat) throws {
        self.device = device
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
        orbDesc.vertexFunction = try fn("swarmVertex")
        orbDesc.fragmentFunction = try fn("swarmFragment")
        orbDesc.colorAttachments[0].pixelFormat = .rgba16Float
        orbDesc.colorAttachments[0].isBlendingEnabled = false
        orbDesc.depthAttachmentPixelFormat = .depth16Unorm
        orbPipeline = try device.makeRenderPipelineState(descriptor: orbDesc)

        let postDesc = MTLRenderPipelineDescriptor()
        postDesc.vertexFunction = try fn("swarmPostVertex")
        postDesc.fragmentFunction = try fn("swarmPostFragment")
        postDesc.colorAttachments[0].pixelFormat = outputFormat
        postPipeline = try device.makeRenderPipelineState(descriptor: postDesc)

        // Точки пишут глубину (одна частица в пикселе); следы-линии только
        // тестируют её (depthMask false в прототипе) — линии не заслоняют точки.
        let dw = MTLDepthStencilDescriptor()
        dw.depthCompareFunction = .less
        dw.isDepthWriteEnabled = true
        let dn = MTLDepthStencilDescriptor()
        dn.depthCompareFunction = .less
        dn.isDepthWriteEnabled = false
        guard let dws = device.makeDepthStencilState(descriptor: dw),
            let dns = device.makeDepthStencilState(descriptor: dn)
        else {
            throw SetupError.noLibrary("нет состояния глубины")
        }
        depthWrite = dws
        depthNoWrite = dns
    }

    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let lib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            // default.metallib собран Xcode — в нём есть функции обоих роёв.
            if lib.makeFunction(name: "swarmVertex") != nil { return lib }
        }
        guard let url = Bundle.module.url(forResource: "OnboardingSwarm", withExtension: "metal") else {
            throw SetupError.noLibrary("в бандле нет ни default.metallib с ройем, ни OnboardingSwarm.metal")
        }
        let source: String
        do { source = try String(contentsOf: url, encoding: .utf8) } catch {
            throw SetupError.noLibrary("не читается OnboardingSwarm.metal: \(error)")
        }
        do { return try device.makeLibrary(source: source, options: nil) } catch {
            throw SetupError.noLibrary("не компилируется OnboardingSwarm.metal: \(error)")
        }
    }

    /// Перевыделить буферы под новый размер (в пикселях буфера).
    func resize(bufW: Int, bufH: Int) {
        guard bufW != self.bufW || bufH != self.bufH, bufW > 0, bufH > 0 else { return }
        self.bufW = bufW
        self.bufH = bufH

        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: bufW, height: bufH, mipmapped: false)
        colorDesc.usage = [.renderTarget, .shaderRead]
        colorDesc.storageMode = .private
        colorTexture = device.makeTexture(descriptor: colorDesc)

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth16Unorm, width: bufW, height: bufH, mipmapped: false)
        depthDesc.usage = .renderTarget
        depthDesc.storageMode = .private
        depthTexture = device.makeTexture(descriptor: depthDesc)
    }

    func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    /// Кодирует оба прохода. `uniforms.mode`/`jit` перекрываются внутри —
    /// вызывающий задаёт всё остальное. Следы рисуются только при `drawLines`.
    func encode(
        into commandBuffer: MTLCommandBuffer,
        output: MTLTexture,
        uniforms base: SwarmUniforms,
        supersample: Int,
        drawLines: Bool
    ) {
        guard let colorTexture, let depthTexture else { return }
        let count = Int(base.count)

        // 1. частицы + следы — в линейный буфер
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

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(orbPipeline)

        // точки
        enc.setDepthStencilState(depthWrite)
        var u = base
        u.mode = 0
        u.jit = 0
        enc.setVertexBytes(&u, length: MemoryLayout<SwarmUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)

        // следы разлёта: три прохода (основная линия + два блюр-хвоста),
        // без записи глубины — линии не заслоняют частицы
        if drawLines {
            enc.setDepthStencilState(depthNoWrite)
            let lineVerts = count * Self.segs * 2
            for j in [Float(0), 1.6, -1.6] {
                var lu = base
                lu.mode = 1
                lu.jit = j
                enc.setVertexBytes(&lu, length: MemoryLayout<SwarmUniforms>.stride, index: 0)
                enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lineVerts)
            }
        }
        enc.endEncoding()

        // 2. семейное сведение + гамма на выход
        let postPass = MTLRenderPassDescriptor()
        postPass.colorAttachments[0].texture = output
        postPass.colorAttachments[0].loadAction = .dontCare
        postPass.colorAttachments[0].storeAction = .store

        guard let postEnc = commandBuffer.makeRenderCommandEncoder(descriptor: postPass) else { return }
        var r = ResolveUniforms(time: base.time, ss: Int32(supersample))
        postEnc.setRenderPipelineState(postPipeline)
        postEnc.setFragmentBytes(&r, length: MemoryLayout<ResolveUniforms>.stride, index: 0)
        postEnc.setFragmentTexture(colorTexture, index: 0)
        postEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        postEnc.endEncoding()
    }
}
