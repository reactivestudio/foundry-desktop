import MetalKit
import SwiftUI

/// Рой онбординга во всю рабочую зону окна установки. Живёт всегда (морфинг из
/// холодной семьи в тёплую и обратно), а по команде `bursting` проигрывает
/// разлёт — сжатие к ядру и расширение за кадр со световыми следами.
///
/// Геометрия привязана к референсному кадру 836 (`refHeight`): окно может расти
/// вниз, но зерно, линза и позиция орба меряются от референса — рой не движется
/// и не меняет размер.
struct OnboardingSwarmView: NSViewRepresentable {
    /// Идёт ли разлёт. При переходе false→true запускается таймлайн 2370ms.
    var bursting: Bool
    /// Прогресс разлёта 0…1 — контейнеру, чтобы синхронно уступить место главному окну.
    var onBurstProgress: ((Double) -> Void)?

    // ── Геометрия роя (та же, что design/loader-logo.html и прототип) ──────
    static let orb: Float = 0.21
    static let zoom: Float = 2.4
    static let taper: Float = 0.5
    static let grain: Float = 0.00504  // эталон «a»
    static let grainLoader: Float = (2.6 * 2.4 / 900) / (orb * 2.4)  // 1.376%
    static let coverage: Float = 6000 * grainLoader * grainLoader
    static let count = Int((coverage / (grain * grain)).rounded())  // 44 701
    static let refHeight: Float = 836
    static let minPoint: Float = 1.8
    static let maxSupersample = 8
    /// Полный разлёт: сжатие ~190ms → расширение ~2.2s.
    static let burstDuration: Double = 2.370
    /// Задержка перед стартом разлёта (как в прототипе).
    static let burstDelay: Double = 0.120

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = false
        // MTKView сам держит drawable = bounds×scale. Раскладку не через
        // ручной drawableSize (его установка внутри drawableSizeWillChange
        // рекурсивно дёргала делегат — переполнение стека), а пересчётом
        // производных из уже данного размера.
        view.autoResizeDrawable = true
        view.layer?.isOpaque = true
        view.delegate = context.coordinator
        context.coordinator.attach(view: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setBursting(bursting)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var parent: OnboardingSwarmView
        private var renderer: OnboardingSwarmRenderer?
        private let start = CACurrentMediaTime()

        // раскладка кадра
        private var supersample = 1
        private var bufW = 0, bufH = 0
        private var pt: Float = 0
        private var kfit: Float = 1
        private var aspect: Float = 1

        // разлёт
        private var bursting = false
        private var burstStart: CFTimeInterval = 0
        private var burst: Float = 0
        private var burstT0: Float = 0
        private var burstT0Set = false
        private var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        // позиция орба в NDC — ровно HERO.y макета (const HERO = {x:0, y:0.32}).
        // При окне 880 канвас = 836 = refHeight, значит kfit = 1.0, и center/fit
        // ниже сводятся к (0, 0.32) и 1.0 — то же, что uCenter/uFit в макете.
        private let heroY: Float = 0.32

        private var occlusionObserver: NSObjectProtocol?

        init(_ parent: OnboardingSwarmView) { self.parent = parent }

        func attach(view: MTKView) {
            guard let device = view.device else { return }
            do {
                renderer = try OnboardingSwarmRenderer(
                    device: device, outputFormat: view.colorPixelFormat)
            } catch {
                assertionFailure("рой онбординга не собрался: \(error)")
            }
            recompute(view: view, pixelSize: view.drawableSize)
            observeOcclusion(view: view)
        }

        func setBursting(_ on: Bool) {
            guard on != bursting else { return }
            bursting = on
            if on {
                burstStart = CACurrentMediaTime() + OnboardingSwarmView.burstDelay
                burst = 0
                burstT0Set = false
            } else {
                burst = 0
                burstT0Set = false
            }
        }

        private func observeOcclusion(view: MTKView) {
            guard occlusionObserver == nil, let window = view.window else { return }
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main
            ) { [weak view, weak window] _ in
                MainActor.assumeIsolated {
                    guard let view, let window else { return }
                    view.isPaused = !window.occlusionState.contains(.visible)
                }
            }
        }

        func stop() {
            if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
            occlusionObserver = nil
        }

        /// Пересчёт производных раскладки из размера drawable (в пикселях). Сам
        /// drawableSize НЕ трогаем — им управляет MTKView (autoResizeDrawable).
        private func recompute(view: MTKView, pixelSize: CGSize) {
            let dpr = Float(view.window?.backingScaleFactor ?? 2.0)
            let w = max(1, Int(pixelSize.width.rounded()))
            let h = max(1, Int(pixelSize.height.rounded()))

            let geo = OnboardingSwarmView.self
            var ss = 1
            while ss < geo.maxSupersample,
                geo.grain * geo.orb * geo.zoom * geo.refHeight * dpr * Float(ss) < geo.minPoint
            {
                ss *= 2
            }
            supersample = ss
            bufW = w * ss
            bufH = h * ss
            pt = geo.grain * geo.orb * geo.zoom * geo.refHeight * dpr * Float(ss)
            // референсный кадр в device-px: refHeight(CSS)·dpr, делим на факт. высоту
            kfit = (geo.refHeight * dpr) / Float(h)
            aspect = Float(w) / Float(h)
            renderer?.resize(bufW: bufW, bufH: bufH)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            recompute(view: view, pixelSize: size)
        }

        func draw(in view: MTKView) {
            guard let renderer,
                bufW > 0, bufH > 0,
                let drawable = view.currentDrawable,
                let cb = renderer.makeCommandBuffer()
            else { return }

            let now = CACurrentMediaTime()
            let sec = Float(now - start)

            // таймлайн разлёта: линейный, весь разгон в кривой масштаба шейдера
            if bursting {
                if reduceMotion {
                    burst = 1
                } else {
                    let p = max(0, (now - burstStart) / OnboardingSwarmView.burstDuration)
                    burst = Float(min(1, p))
                }
                parent.onBurstProgress?(Double(burst))
            }

            // заморозка внутренней жизни на старте рывка (uT0)
            if burst > 0.08 {
                if !burstT0Set {
                    burstT0 = sec
                    burstT0Set = true
                }
            } else {
                burstT0Set = false
            }

            let geo = OnboardingSwarmView.self
            var u = OnboardingSwarmRenderer.SwarmUniforms()
            u.time = reduceMotion && !bursting ? 0 : sec
            u.count = Float(geo.count)
            u.res = SIMD2<Float>(Float(bufW), Float(bufH))
            u.zoom = geo.zoom
            u.pt = pt
            u.taper = geo.taper
            u.aspect = aspect
            // позиция орба в NDC референсного кадра, пересчёт в фактический:
            // y' = 1 − (1 − y)·KFIT; по x орб центрован.
            u.center = SIMD2<Float>(0, 1 - (1 - heroY) * kfit)
            // кинематографичный наезд камеры в момент рывка (+40% по кривой)
            let xg = max(0, (burst - 0.08) / 0.92)
            let gb = xg * xg * (1.4 - 0.4 * xg)
            u.fit = kfit * (1 + 0.40 * gb)
            u.burst = burst
            u.step = 0.015
            u.t0 = burstT0Set ? burstT0 : sec

            let drawLines = burst > 0.08 && burst < 1
            renderer.encode(
                into: cb, output: drawable.texture,
                uniforms: u, supersample: supersample, drawLines: drawLines)
            cb.present(drawable)
            cb.commit()
        }
    }
}
