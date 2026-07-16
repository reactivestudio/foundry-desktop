import Foundation
import FoundryFeatures
import Metal

// Замер роя на настоящей Metal-железке. Считает не «сколько кадров успеваем»,
// а сколько ГПУ реально занят на кадр: gpuEndTime - gpuStartTime командного
// буфера. Это то число, из которого видно, тормозит логотип систему или нет.
//
// Офскрин, без окна: показывать нечего, а показ добавил бы к замеру композитор.

struct Case {
    let label: String
    let preset: OrbSwarmConfig.Preset
    let size: Float
}

let scale: Float = 2.0        // Retina
let warmup = 20
let frames = 200

let cases: [Case] = [
    Case(label: "орб в тулбаре 22", preset: .standard, size: 22),
    Case(label: "логотип 64",       preset: .standard, size: 64),
    Case(label: "логотип 128",      preset: .standard, size: 128),
    Case(label: "логотип 128 fine", preset: .fine,     size: 128),
    Case(label: "логотип 256",      preset: .standard, size: 256),
    Case(label: "логотип 512",      preset: .standard, size: 512),
    Case(label: "логотип 512 fine", preset: .fine,     size: 512),
    Case(label: "логотип 64 fine",  preset: .fine,     size: 64),
    Case(label: "логотип 32",       preset: .standard, size: 32),
]

guard let device = MTLCreateSystemDefaultDevice() else {
    print("нет Metal-устройства")
    exit(1)
}

print("устройство: \(device.name)")
print("единая память: \(device.hasUnifiedMemory)")
print("")

// Разовая цена: сборка библиотеки шейдеров из исходника.
let libStart = Date()
let probe = try OrbSwarmRenderer(
    device: device,
    config: OrbSwarmConfig(preset: .standard, size: 64, scale: scale),
    outputFormat: .bgra8Unorm)
let libMs = Date().timeIntervalSince(libStart) * 1000
_ = probe
print(String(format: "сборка шейдеров при старте: %.0f мс (разово)", libMs))
print("")

func pad(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
}
func rpad(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
}

print(pad("конфигурация", 19) + rpad("частиц", 7) + rpad("SS", 4) + rpad("буфер", 7)
      + rpad("точка", 7) + rpad("част/px", 8)
      + rpad("GPU мс", 9) + rpad("макс мс", 9) + rpad("% кадра", 9))

for c in cases {
    let cfg = OrbSwarmConfig(preset: c.preset, size: c.size, scale: scale)
    let renderer = try OrbSwarmRenderer(device: device, config: cfg, outputFormat: .bgra8Unorm)

    let outDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: cfg.output, height: cfg.output, mipmapped: false)
    outDesc.usage = [.renderTarget, .shaderRead]
    outDesc.storageMode = .private
    guard let out = device.makeTexture(descriptor: outDesc) else { continue }

    var samples: [Double] = []
    samples.reserveCapacity(frames)

    for i in 0..<(warmup + frames) {
        guard let cb = renderer.makeCommandBuffer() else { continue }
        renderer.encode(into: cb, output: out, time: Float(i) * (1.0 / 60.0))
        cb.commit()
        cb.waitUntilCompleted()
        if i >= warmup {
            samples.append((cb.gpuEndTime - cb.gpuStartTime) * 1000)
        }
    }

    samples.sort()
    let median = samples[samples.count / 2]
    let worst = samples[samples.count - 1]
    // Доля кадра при 60 fps: бюджет 16.7 мс на ВСЁ, что рисует система.
    let share = median / 16.67 * 100

    var warn = ""
    if cfg.unreadable { warn += "  ⚠ пятно: \(String(format: "%.1f", cfg.particlesPerPixel)) частиц/px" }
    if cfg.flickers { warn += "  ⚠ мельтешит" }
    print(pad(c.label, 19) + rpad("\(cfg.count)", 7) + rpad("×\(cfg.supersample)", 4)
          + rpad("\(cfg.buffer)", 7)
          + rpad(String(format: "%.2f", cfg.pointSizeOnScreen), 7)
          + rpad(String(format: "%.2f", cfg.particlesPerPixel), 8)
          + rpad(String(format: "%.3f", median), 9)
          + rpad(String(format: "%.3f", worst), 9)
          + rpad(String(format: "%.2f%%", share), 9) + warn)
}

print("")
print("GPU мс — медиана по \(frames) кадрам, время занятости GPU на один кадр.")
print("% кадра — доля бюджета 16.7 мс при 60 fps.")

// ── Снимки ──────────────────────────────────────────────────────────────────
// Порт обязан совпадать с прототипом в design/. Расхождение — баг, а не вкус,
// поэтому кадры пишутся на диск и сравниваются с ним глазами и по палитре.
if CommandLine.arguments.contains("--dump") {
    let dir = URL(fileURLWithPath: "/tmp/orbshots")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for c in cases {
        let cfg = OrbSwarmConfig(preset: c.preset, size: c.size, scale: scale)
        let r = try OrbSwarmRenderer(device: device, config: cfg, outputFormat: .rgba8Unorm)
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: cfg.output, height: cfg.output, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let out = device.makeTexture(descriptor: d), let cb = r.makeCommandBuffer() else { continue }
        // Кадр 20 — тот же, что снимался с прототипа.
        r.encode(into: cb, output: out, time: 20.0)
        cb.commit(); cb.waitUntilCompleted()

        let count = cfg.output * cfg.output * 4
        var bytes = [UInt8](repeating: 0, count: count)
        out.getBytes(&bytes, bytesPerRow: cfg.output * 4,
                     from: MTLRegionMake2D(0, 0, cfg.output, cfg.output), mipmapLevel: 0)
        let name = "\(c.preset.rawValue)-\(Int(c.size)).raw"
        try Data(bytes).write(to: dir.appendingPathComponent(name))
        print("\(name) — \(cfg.output)×\(cfg.output)")
    }
}
