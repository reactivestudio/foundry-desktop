import MetalKit
import SwiftUI

/// Рой онбординга во всю рабочую зону окна установки. Живёт всегда (морфинг из
/// холодной семьи в тёплую и обратно), а по команде `isBursting` проигрывает
/// разлёт — сжатие к ядру и расширение за кадр со световыми следами.
///
/// Геометрия привязана к референсному кадру 836 (`refHeight`): окно может расти
/// вниз, но зерно, линза и позиция орба меряются от референса — рой не движется
/// и не меняет размер.
struct OnboardingSwarmView: NSViewRepresentable {
    /// Идёт ли разлёт. При переходе false→true запускается таймлайн 2370ms.
    var isBursting: Bool
    /// Прогресс разлёта 0…1 — контейнеру, чтобы синхронно уступить место главному окну.
    var onBurstProgress: ((Double) -> Void)?

    // ── Геометрия роя (та же, что design/loader-logo.html и прототип) ──────
    static let orbBodyFraction: Float = 0.21
    static let zoom: Float = 2.4
    static let taper: Float = 0.5
    static let grain: Float = 0.00504  // эталон «a»
    static let loaderGrain: Float = (2.6 * 2.4 / 900) / (orbBodyFraction * 2.4)  // 1.376%
    static let coverage: Float = 6000 * loaderGrain * loaderGrain
    static let particleCount = Int((coverage / (grain * grain)).rounded())  // 44 701
    static let refHeight: Float = 836
    /// Насколько опустить облако вниз от позиции макета, в экранных точках. Верхняя
    /// кромка вида остаётся на y=0, само облако ниже — частицы не доходят до кромки
    /// окна (клип сверху режет пустой fon, без линии среза).
    static let heroDropPt: Float = 20
    static let minPointSize: Float = 1.8
    /// Множитель размера частицы (1.0 = как было). Суперсэмпл выбирается по
    /// неуменьшенному размеру, поэтому мельчить точку можно без потери резкости.
    static let pointScale: Float = 0.85
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
        // Рой прозрачен: resolve пишет premultiplied-альфу (частицы поверх пустоты),
        // фон даёт нижний SwiftUI-слой OB.backdrop. Непрозрачный слой залил бы его.
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        // Обрезать рой по форме окна: SwiftUI-`.clipShape` дровабл CAMetalLayer не
        // режет — частицы квадратными углами вылезали за скруглённую кромку на обои.
        // Маска по слою НЕ меняет размер/позицию роя (геометрия та же), только
        // клиппит вывод. Радиус/кривая — как у окна (RoundedRectangle 12 .continuous).
        view.layer?.cornerRadius = 12
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.delegate = context.coordinator
        context.coordinator.attach(view: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setBursting(isBursting)
        // Окна у вида в makeNSView ещё нет — наблюдатель окклюзии там не встаёт.
        // Доустанавливаем его здесь, когда окно уже привязано (идемпотентно —
        // guard внутри ставит ровно один раз). Зеркало OrbSwarmView.
        context.coordinator.observeOcclusion(view: view)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var parent: OnboardingSwarmView
        private var renderer: OnboardingSwarmRenderer?
        private let startTime = CACurrentMediaTime()

        // раскладка кадра
        private var supersample = 1
        private var bufferWidth = 0, bufferHeight = 0
        private var pointSize: Float = 0
        private var fitRatio: Float = 1
        private var aspect: Float = 1
        private var viewHeightPt: Float = 880  // высота вида в точках (для перевода px→NDC)

        // разлёт
        private var isBursting = false
        private var burstStart: CFTimeInterval = 0
        private var burst: Float = 0
        private var frozenBurstTime: Float = 0
        private var didFreezeBurstTime = false
        private var shouldReduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        // позиция орба в NDC — ровно HERO.y макета (const HERO = {x:0, y:0.32}).
        // При окне 880 канвас = 836 = refHeight, значит fitRatio = 1.0, и center/fit
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
                // Релиз: assert — no-op. Рой останется пустым, но сбой сборки
                // рендерера уходит в системный лог на уровне fault.
                FeatureLog.swarm.fault(
                    "рой онбординга не собрался: \(error.localizedDescription, privacy: .public)")
            }
            recomputeLayout(view: view, pixelSize: view.drawableSize)
            observeOcclusion(view: view)
        }

        func setBursting(_ isBursting: Bool) {
            guard isBursting != self.isBursting else { return }
            self.isBursting = isBursting
            if isBursting {
                burstStart = CACurrentMediaTime() + OnboardingSwarmView.burstDelay
                burst = 0
                didFreezeBurstTime = false
            } else {
                burst = 0
                didFreezeBurstTime = false
            }
        }

        func observeOcclusion(view: MTKView) {
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
        private func recomputeLayout(view: MTKView, pixelSize: CGSize) {
            let dpr = Float(view.currentBackingScale)
            let w = max(1, Int(pixelSize.width.rounded()))
            let h = max(1, Int(pixelSize.height.rounded()))

            let geometry = OnboardingSwarmView.self
            let factor = OrbSwarmConfig.supersamplingFactor(
                perStep: geometry.grain * geometry.orbBodyFraction * geometry.zoom * geometry.refHeight
                    * dpr,
                target: geometry.minPointSize, cap: geometry.maxSupersample)
            supersample = factor
            bufferWidth = w * factor
            bufferHeight = h * factor
            pointSize =
                geometry.grain * geometry.orbBodyFraction * geometry.zoom * geometry.refHeight * dpr
                * Float(factor)
            // референсный кадр в device-px: refHeight(CSS)·dpr, делим на факт. высоту
            fitRatio = (geometry.refHeight * dpr) / Float(h)
            aspect = Float(w) / Float(h)
            viewHeightPt = Float(h) / dpr
            renderer?.resize(bufferWidth: bufferWidth, bufferHeight: bufferHeight)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            recomputeLayout(view: view, pixelSize: size)
        }

        func draw(in view: MTKView) {
            guard let renderer,
                bufferWidth > 0, bufferHeight > 0,
                let drawable = view.currentDrawable,
                let commandBuffer = renderer.makeCommandBuffer()
            else { return }

            let now = CACurrentMediaTime()
            let seconds = Float(now - startTime)

            advanceBurstTimeline(now: now, seconds: seconds)
            let uniforms = makeUniforms(seconds: seconds)

            let drawsTrails = burst > 0.08 && burst < 1
            renderer.encode(
                into: commandBuffer, output: drawable.texture,
                uniforms: uniforms, supersample: supersample, drawsTrails: drawsTrails)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        /// Продвигает состояние разлёта на кадр: линейный прогресс `burst` (весь
        /// разгон — в кривой масштаба шейдера) и заморозку внутренней жизни `t0`
        /// на старте рывка. Мутирует burst/frozenBurstTime/didFreezeBurstTime и уведомляет контейнер.
        private func advanceBurstTimeline(now: CFTimeInterval, seconds: Float) {
            // таймлайн разлёта: линейный, весь разгон в кривой масштаба шейдера
            if isBursting {
                if shouldReduceMotion {
                    burst = 1
                } else {
                    let progress = max(0, (now - burstStart) / OnboardingSwarmView.burstDuration)
                    burst = Float(min(1, progress))
                }
                parent.onBurstProgress?(Double(burst))
            }

            // заморозка внутренней жизни на старте рывка (uT0)
            if burst > 0.08 {
                if !didFreezeBurstTime {
                    frozenBurstTime = seconds
                    didFreezeBurstTime = true
                }
            } else {
                didFreezeBurstTime = false
            }
        }

        /// Собирает SwarmUniforms кадра из текущей раскладки и состояния разлёта
        /// (после `advanceBurstTimeline`): позиция орба в NDC, кинематографичный
        /// наезд камеры на рывке, замороженный `t0`.
        private func makeUniforms(seconds: Float) -> OnboardingSwarmRenderer.SwarmUniforms {
            let geometry = OnboardingSwarmView.self
            var u = OnboardingSwarmRenderer.SwarmUniforms()
            u.time = shouldReduceMotion && !isBursting ? 0 : seconds
            u.count = Float(geometry.particleCount)
            u.resolution = SIMD2<Float>(Float(bufferWidth), Float(bufferHeight))
            u.zoom = geometry.zoom
            u.pointSize = pointSize * geometry.pointScale
            u.taper = geometry.taper
            u.aspect = aspect
            // позиция орба в NDC референсного кадра, пересчёт в фактический:
            // y' = 1 − (1 − y)·KFIT; по x орб центрован. Минус heroDropPt — опустить
            // облако на N экранных точек (NDC 2.0 = viewHeightPt; +y вверх → вычитаем).
            let dropNDC = geometry.heroDropPt * 2 / viewHeightPt
            u.center = SIMD2<Float>(0, (1 - (1 - heroY) * fitRatio) - dropNDC)
            // кинематографичный наезд камеры в момент рывка (+40% по кривой)
            let pushProgress = max(0, (burst - 0.08) / 0.92)
            let pushEase = pushProgress * pushProgress * (1.4 - 0.4 * pushProgress)
            u.fit = fitRatio * (1 + 0.40 * pushEase)
            u.burst = burst
            u.step = 0.015
            u.t0 = didFreezeBurstTime ? frozenBurstTime : seconds
            return u
        }
    }
}
