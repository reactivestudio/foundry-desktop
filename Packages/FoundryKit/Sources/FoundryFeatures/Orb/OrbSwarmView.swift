import MetalKit
import SwiftUI

/// Рой «Восход» в SwiftUI.
///
/// Считать рой дёшево: на M1 Max логотип 64 занимает GPU на 0.212 мс в кадре —
/// 1.3% бюджета при 60 fps. Дорого другое: будить GPU, когда показывать нечего.
/// Поэтому вид анимирует только пока `animating`, а в покое замирает на кадре и
/// кадров не просит.
///
/// Ниже 64 pt рой не имеет смысла: зерно не помещается в пиксель, сведение
/// усредняет частицы в сплошное пятно, и «рой» перестаёт читаться роем —
/// остаётся цветная клякса. Для мелких мест нужен не этот вид.
public struct OrbSwarmView: View {
    /// Размер, ниже которого рой вырождается в пятно. Не порог вкуса: при 22 pt
    /// сведение ×8 усредняет 11 175 частиц в 44 пикселя, и зерна не остаётся.
    public static let minimumUsefulSize: CGFloat = 64

    /// Холст роя — тот самый почти-чёрный, на котором рой утверждён.
    ///
    /// Снято с кадра, а не выведено из `clearColor`: рой считает в ЛИНЕЙНОМ
    /// цвете, а гамму (`pow(c, 1/2.2)`, см. `OrbSwarm.metal`) возвращает
    /// пост-пасс — поэтому линейные 0.00021/0.00033/0.00160 на экране дают
    /// именно #05060C.
    ///
    /// Константа общая нарочно: подложка под роем обязана быть ровно этой, иначе
    /// непрозрачный слой роя проступит на фоне квадратом. Раньше фон ленты был
    /// задан отдельно (#08080F) и расходился с роем на 3/255.
    public static let canvas = Color(red: 5 / 255, green: 6 / 255, blue: 12 / 255)

    private let size: CGFloat
    private let preset: OrbSwarmConfig.Preset
    private let animating: Bool

    public init(size: CGFloat = 64,
                preset: OrbSwarmConfig.Preset = .standard,
                animating: Bool = true) {
        self.size = size
        self.preset = preset
        self.animating = animating
    }

    public var body: some View {
        OrbSwarmLayer(size: size, preset: preset, animating: animating)
            .frame(width: size, height: size)
    }
}

private struct OrbSwarmLayer: NSViewRepresentable {
    let size: CGFloat
    let preset: OrbSwarmConfig.Preset
    let animating: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        // Глубина живёт в собственном буфере рендерера, у MTKView её нет.
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = false
        view.autoResizeDrawable = false
        // Фон роя непрозрачен (#05060C) — слой тоже, иначе композитор зря
        // смешивал бы его с подложкой.
        view.layer?.isOpaque = true
        view.delegate = context.coordinator
        context.coordinator.configure(view: view, size: size, preset: preset)
        context.coordinator.setAnimating(animating, view: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.configure(view: view, size: size, preset: preset)
        context.coordinator.setAnimating(animating, view: view)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private var renderer: OrbSwarmRenderer?
        private var config: OrbSwarmConfig?
        private var start: CFTimeInterval = CACurrentMediaTime()
        /// Время последнего нарисованного кадра. В покое рой замирает на нём,
        /// а не отматывается к нулю: иначе пауза дёргала бы картинку.
        private var frozen: Float = 0
        private var animating = true
        private var occlusionObserver: NSObjectProtocol?

        func configure(view: MTKView, size: CGFloat, preset: OrbSwarmConfig.Preset) {
            guard let device = view.device else { return }
            let scale = Float(view.window?.backingScaleFactor ?? 2.0)
            let cfg = OrbSwarmConfig(preset: preset, size: Float(size), scale: scale)
            guard cfg != config else { return }

            let drawableSide = cfg.output
            view.drawableSize = CGSize(width: drawableSide, height: drawableSide)

            if let renderer {
                renderer.update(config: cfg)
            } else {
                do {
                    renderer = try OrbSwarmRenderer(
                        device: device, config: cfg, outputFormat: view.colorPixelFormat)
                } catch {
                    // Без роя вид остаётся пустым — падать из-за логотипа нельзя.
                    assertionFailure("рой не собрался: \(error)")
                    return
                }
            }
            config = cfg
            applyFrameRate(view: view, preset: preset)
            observeOcclusion(view: view)
        }

        /// Частота кадров — из порога пресета, а не из экономии.
        ///
        /// 30 fps тут мало, хотя рой и кажется медленным: за кадр частица
        /// проходит 1.4 своего диаметра, след рвётся и видна ступенька. Порог
        /// standard — 41 fps, fine — 82 (зерно вдвое мельче при том же сдвиге).
        ///
        /// Экономить нечем: на M1 Max логотип 64 занимает GPU на 0.212 мс, и
        /// при 60 fps это 1.3% его времени. Разница между 30 и 60 в расходе
        /// незаметна, а в картинке — заметна.
        private func applyFrameRate(view: MTKView, preset: OrbSwarmConfig.Preset) {
            let displayHz = view.window?.screen?.maximumFramesPerSecond ?? 60
            view.preferredFramesPerSecond = OrbSwarmConfig.achievableFrameRate(
                preset: preset, displayHz: displayHz)
            // Больше, чем умеет экран, не выпросишь — но и делать вид, что порог
            // выполнен, нельзя: на 60 Гц fine недостижим, и это надо знать, а не
            // молча получить шагающий рой.
            assert(
                !OrbSwarmConfig.steps(preset: preset, displayHz: displayHz),
                "\(preset.rawValue) требует \(preset.minimumFramesPerSecond) fps,"
                    + " экран даёт \(displayHz) — рой будет шагать. Нужен .standard.")
        }

        /// Перекрытое или свёрнутое окно кадров не просит: рисовать в никуда —
        /// это чистый расход батареи.
        private func observeOcclusion(view: MTKView) {
            guard occlusionObserver == nil, let window = view.window else { return }
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main
            ) { [weak self, weak view, weak window] _ in
                // Уведомление приходит на главную очередь (queue: .main), но для
                // компилятора замыкание Sendable, а occlusionState и MTKView
                // изолированы главным актором. Окно захвачено, а не взято из
                // note: сам объект уведомления через границу не протащить.
                MainActor.assumeIsolated {
                    guard let self, let view, let window else { return }
                    let visible = window.occlusionState.contains(.visible)
                    view.isPaused = !(self.animating && visible)
                }
            }
        }

        func setAnimating(_ on: Bool, view: MTKView) {
            guard on != animating else { return }
            if on {
                // Продолжаем с замороженного места, а не с нуля.
                start = CACurrentMediaTime() - CFTimeInterval(frozen)
            }
            animating = on
            view.isPaused = !on
            view.enableSetNeedsDisplay = !on
            if !on { view.needsDisplay = true }   // дорисовать замерший кадр
        }

        func stop() {
            if let occlusionObserver {
                NotificationCenter.default.removeObserver(occlusionObserver)
            }
            occlusionObserver = nil
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let renderer,
                  let drawable = view.currentDrawable,
                  let cb = renderer.makeCommandBuffer() else { return }
            let t = animating ? Float(CACurrentMediaTime() - start) : frozen
            if animating { frozen = t }
            renderer.encode(into: cb, output: drawable.texture, time: t)
            cb.present(drawable)
            cb.commit()
        }
    }
}
