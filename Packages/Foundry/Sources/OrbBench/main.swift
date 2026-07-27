import Core
import Foundation
import Metal

// Замер роя на настоящей Metal-железке. Считает не «сколько кадров успеваем»,
// а сколько ГПУ реально занят на кадр: gpuEndTime - gpuStartTime командного
// буфера. Это то число, из которого видно, тормозит логотип систему или нет.
//
// Офскрин, без окна: показывать нечего, а показ добавил бы к замеру композитор.

struct BenchmarkCase {
    let label: String
    let preset: OrbSwarmConfig.Preset
    let size: Float
}

let scale: Float = 2.0  // Retina
let warmup = 20
let frames = 200

let cases: [BenchmarkCase] = [
    BenchmarkCase(label: "орб в тулбаре 22", preset: .standard, size: 22),
    BenchmarkCase(label: "логотип 64", preset: .standard, size: 64),
    BenchmarkCase(label: "логотип 128", preset: .standard, size: 128),
    BenchmarkCase(label: "логотип 128 fine", preset: .fine, size: 128),
    BenchmarkCase(label: "логотип 256", preset: .standard, size: 256),
    BenchmarkCase(label: "логотип 512", preset: .standard, size: 512),
    BenchmarkCase(label: "логотип 512 fine", preset: .fine, size: 512),
    BenchmarkCase(label: "логотип 64 fine", preset: .fine, size: 64),
    BenchmarkCase(label: "логотип 32", preset: .standard, size: 32),
]

guard let device = MTLCreateSystemDefaultDevice() else {
    print("нет Metal-устройства")
    exit(1)
}

print("устройство: \(device.name)")
print("единая память: \(device.hasUnifiedMemory)")
print("")

// Разовая цена: сборка библиотеки шейдеров из исходника.
let libraryStart = Date()
let probe = try OrbSwarmRenderer(
    device: device,
    config: OrbSwarmConfig(preset: .standard, size: 64, scale: scale),
    outputFormat: .bgra8Unorm)
let libraryMilliseconds = Date().timeIntervalSince(libraryStart) * 1000
_ = probe
print(String(format: "сборка шейдеров при старте: %.0f мс (разово)", libraryMilliseconds))
print("")

func padTrailing(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}
func padLeading(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
}

print(
    padTrailing("конфигурация", 19) + padLeading("частиц", 7) + padLeading("SS", 4)
        + padLeading("буфер", 7)
        + padLeading("точка", 7) + padLeading("част/px", 8)
        + padLeading("GPU мс", 9) + padLeading("макс мс", 9) + padLeading("% кадра", 9))

for benchmarkCase in cases {
    let config = OrbSwarmConfig(preset: benchmarkCase.preset, size: benchmarkCase.size, scale: scale)
    let renderer = try OrbSwarmRenderer(device: device, config: config, outputFormat: .bgra8Unorm)

    let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: config.outputSide, height: config.outputSide, mipmapped: false)
    outputDesc.usage = [.renderTarget, .shaderRead]
    outputDesc.storageMode = .private
    guard let output = device.makeTexture(descriptor: outputDesc) else { continue }

    var samples: [Double] = []
    samples.reserveCapacity(frames)

    for frameIndex in 0..<(warmup + frames) {
        guard let commandBuffer = renderer.makeCommandBuffer() else { continue }
        renderer.encode(into: commandBuffer, output: output, time: Float(frameIndex) * (1.0 / 60.0))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if frameIndex >= warmup {
            samples.append((commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1000)
        }
    }

    samples.sort()
    let median = samples[samples.count / 2]
    let worst = samples[samples.count - 1]
    // Доля кадра при 60 fps: бюджет 16.7 мс на ВСЁ, что рисует система.
    let share = median / 16.67 * 100

    var warn = ""
    if config.unreadable {
        warn += "  ⚠ пятно: \(String(format: "%.1f", config.particlesPerPixel)) частиц/px"
    }
    if config.flickers { warn += "  ⚠ мельтешит" }
    print(
        padTrailing(benchmarkCase.label, 19) + padLeading("\(config.particleCount)", 7)
            + padLeading("×\(config.supersample)", 4)
            + padLeading("\(config.bufferSide)", 7)
            + padLeading(String(format: "%.2f", config.pointSizeOnScreen), 7)
            + padLeading(String(format: "%.2f", config.particlesPerPixel), 8)
            + padLeading(String(format: "%.3f", median), 9)
            + padLeading(String(format: "%.3f", worst), 9)
            + padLeading(String(format: "%.2f%%", share), 9) + warn)
}

print("")
print("GPU мс — медиана по \(frames) кадрам, время занятости GPU на один кадр.")
print("% кадра — доля бюджета 16.7 мс при 60 fps.")

// ── Снимки: общая механика ───────────────────────────────────────────────────
// Обе развёртки (`--dump`, `--loaders`) пишут .raw-кадры одинаково — расходятся
// лишь конфигурацией, точками цикла и схемой имён. Вынесено, чтобы механика
// снимка была одна.

/// Общий для снимков выход: rgba8Unorm, .shared (CPU читает getBytes).
func makeSnapshotOutput(_ config: OrbSwarmConfig) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: config.outputSide, height: config.outputSide, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .shared
    return device.makeTexture(descriptor: descriptor)
}

/// Рендерит один кадр цикла и возвращает его пиксели (nil — если команд-буфер
/// не создался). Читает ровно ту область, что и рисует.
func renderSnapshot(
    _ renderer: OrbSwarmRenderer, _ config: OrbSwarmConfig, into output: MTLTexture, at time: Float
) -> Data? {
    guard let commandBuffer = renderer.makeCommandBuffer() else { return nil }
    renderer.encode(into: commandBuffer, output: output, time: time)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    let count = config.outputSide * config.outputSide * 4
    var bytes = [UInt8](repeating: 0, count: count)
    output.getBytes(
        &bytes, bytesPerRow: config.outputSide * 4,
        from: MTLRegionMake2D(0, 0, config.outputSide, config.outputSide), mipmapLevel: 0)
    return Data(bytes)
}

// ── Снимки ──────────────────────────────────────────────────────────────────
// Порт обязан совпадать с прототипом в design/. Расхождение — баг, а не вкус,
// поэтому кадры пишутся на диск и сравниваются с ним глазами и по палитре.
if CommandLine.arguments.contains("--dump") {
    let dir = URL(fileURLWithPath: "/tmp/orbshots")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // Цикл роя — 54 с; берём девять точек, чтобы поймать обе семьи и переходы.
    let times: [Float] = stride(from: Float(0), to: 54, by: 6).map { $0 }
    for benchmarkCase in cases {
        let config = OrbSwarmConfig(
            preset: benchmarkCase.preset, size: benchmarkCase.size, scale: scale)
        let renderer = try OrbSwarmRenderer(device: device, config: config, outputFormat: .rgba8Unorm)
        guard let output = makeSnapshotOutput(config) else { continue }

        // Логотип — это ОДИН кадр из цикла в 54 с, и какой именно достанется
        // зрителю, никто не выбирает. Поэтому снимаем не «кадр 20», а развёртку
        // по циклу: если форма читается только иногда, логотипом это не годится.
        for time in times {
            guard let data = renderSnapshot(renderer, config, into: output, at: time) else { continue }
            let name = "\(benchmarkCase.preset.rawValue)-\(Int(benchmarkCase.size))-t\(Int(time)).raw"
            try data.write(to: dir.appendingPathComponent(name))
            print("\(name) — \(config.outputSide)×\(config.outputSide)")
        }
    }
}

// ── Лоадеры для мелких размеров ──────────────────────────────────────────────
// Рендерит именованные пресеты из кода (Loader.px32/px64) — проверяем ровно то,
// что зашито, а не отдельные числа. Крупность и число частиц там развязаны.
if CommandLine.arguments.contains("--loaders") {
    let dir = URL(fileURLWithPath: "/tmp/orbshots")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // Восемь фаз цикла: лоадер крутится, и красота — это весь цикл, не один кадр.
    let times: [Float] = stride(from: Float(0), to: 54, by: 6.75).map { $0 }

    print("")
    print("=== лоадеры ===")
    print(
        padTrailing("пресет", 10) + padLeading("N", 7) + padLeading("SS", 5)
            + padLeading("точка", 8) + padLeading("част/px", 9) + padLeading("порог", 7) + "  вердикт")
    for loader in OrbSwarmConfig.Loader.allCases {
        let config = OrbSwarmConfig(loader: loader, scale: scale)
        let renderer = try OrbSwarmRenderer(device: device, config: config, outputFormat: .rgba8Unorm)
        guard let output = makeSnapshotOutput(config) else { continue }

        for time in times {
            guard let data = renderSnapshot(renderer, config, into: output, at: time) else { continue }
            let name = "loader-\(loader.rawValue)-t\(Int(time)).raw"
            try data.write(to: dir.appendingPathComponent(name))
        }
        var warn = config.unreadable ? "  ⚠ пятно" : "ок"
        if config.flickers { warn += " ⚠ мельтешит" }
        print(
            padTrailing(loader.rawValue, 10) + padLeading("\(config.particleCount)", 7)
                + padLeading("×\(config.supersample)", 5)
                + padLeading(String(format: "%.2f", config.pointSizeOnScreen), 8)
                + padLeading(String(format: "%.2f", config.particlesPerPixel), 9)
                + padLeading("\(config.minimumFramesPerSecond)", 7) + "  " + warn)
    }
}
