import AppKit
import SwiftUI

/// Корень приложения: при первом запуске показывает мастер онбординга поверх
/// главного окна, после разлёта уступает ему место. Флаг `didFinishOnboarding`
/// в AppStorage гейтит первый запуск.
public struct FoundryRootView: View {
    @AppStorage("didFinishOnboarding") private var done = false
    @State private var store = RunStore()
    @State private var winOpacity: Double = 1
    @State private var winScale: CGFloat = 1

    public init() {}

    public var body: some View {
        ZStack {
            // главное окно всегда под мастером — разлёт открывает его
            RunConsoleView()
                .environment(store)

            if !done {
                OnboardingContainer(
                    onReveal: {
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.6)) {
                            winOpacity = 0
                            winScale = 0.985
                        }
                    },
                    onFinished: { done = true },
                    onSkip: { done = true })
                .opacity(winOpacity)
                .scaleEffect(winScale)
                .transition(.opacity)
            }
        }
        .background(WindowConfigurator(onboarding: !done))
    }
}

/// Мастер: рой на фоне рабочей зоны, экран поверх, подвал с точками и выходом.
struct OnboardingContainer: View {
    let onReveal: () -> Void
    let onFinished: () -> Void
    let onSkip: () -> Void

    @State private var model = OnboardingModel()

    private let titlebar: CGFloat = 44

    var body: some View {
        ZStack(alignment: .top) {
            OB.bg.ignoresSafeArea()

            // рой — во всю рабочую зону под титлбаром (референсный кадр 836)
            OnboardingSwarmView(bursting: model.bursting,
                                onBurstProgress: { model.burstProgress($0) })
                .padding(.top, titlebar)
                .ignoresSafeArea()

            // завеса `.ob-veil`: гасит рой к низу, чтобы решение экрана читалось
            // на чистом фоне, а не на частицах. Три состояния кросс-фейдятся 640ms.
            // Без неё рабочие экраны висели прямо на рое — главный отличавший их от
            // макета изъян и источник «рендерящихся после» теней (карточкам нужна
            // сплошная тёмная подложка сзади).
            veil
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(model.bursting ? 0 : 1)

            // контент: ob-stage (flex:1) между титлбаром и подвалом + подвал.
            // Верх/низ экрана — по макету: приветствие/Agent/Готово к низу
            // (flex-end), рабочие экраны к верху (padding-top 130).
            VStack(spacing: 0) {
                Color.clear.frame(height: titlebar)     // резерв под титлбар
                stageRegion
                footer
                    .padding(.horizontal, 24)
                    // подвал прижат к низу как .ob-foot: margin снизу s5 = 24
                    .padding(.bottom, 24)
            }

            // свой титлбар как в макете: тонкий подъём + нижняя волосина, имя
            // слева после «светофора» (нативный центрированный титул скрыт)
            titlebarBar
        }
        // окно жёстко 720×880 (ставит WindowConfigurator); содержимое заполняет
        // весь кадр, включая 44px под титлбаром (fullSizeContentView)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // пагинация с клавиатуры: ← назад, → вперёд (монитор надёжнее onKeyPress,
        // которому нужен фокус — его перехватывает кнопка экрана)
        .background(KeyCatcher(onLeft: { model.goPrev() }, onRight: { model.goNext() }))
        .onAppear {
            model.onReveal = onReveal
            model.onFinished = onFinished
        }
    }

    /// Полоса титлбара 44px: градиент-подъём (белый 0.05→0.015), нижняя волосина
    /// border.subtle, имя «Foundry — Setup» 12/500 третичным слева — отступ 80
    /// расчищает нативный «светофор». Кнопки окна рисует система поверх.
    private var titlebarBar: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.015)],
                           startPoint: .top, endPoint: .bottom)
            Text("Foundry — Setup")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OB.tTertiary)
                .padding(.leading, 80)
        }
        .frame(height: titlebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    /// Рабочая зона `.ob-stage` (flex:1) между титлбаром и подвалом. Экран внутри
    /// прижимается к низу или к верху ровно как в макете; боковой отступ s5=24 и
    /// нижний s5=24 — общие для всех экранов, доп. нижний воздух даёт screenPadBottom.
    private var stageRegion: some View {
        Group {
            if model.bottomPinned {
                VStack(spacing: 0) {
                    screenContent
                    if model.screenPadBottom > 0 {
                        Color.clear.frame(height: model.screenPadBottom)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 130)      // .ob-stage padding-top
                    screenContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 24)                        // .ob-stage боковой s5
        .padding(.bottom, 24)                            // .ob-stage нижний s5
    }

    /// Экран с анимацией входа/выхода (двухтактный переход): гашение прозрачности
    /// и доезд снизу на 22px; на время движения контент запекается в текстуру.
    private var screenContent: some View {
        screen
            .frame(maxWidth: .infinity)
            .flattenWhileMoving(model.animating)
            .opacity(model.contentOpacity)
            .offset(y: model.contentOffset)
    }

    /// Завеса поверх роя (`.ob-veil`): два градиента-слоя, кросс-фейд по состоянию.
    /// standard — солид с 22% высоты (рабочие экраны); low — солид с 67% (Agent,
    /// затемнение только под карточками). На hero-full оба слоя сняты.
    private var veil: some View {
        ZStack {
            LinearGradient(stops: Self.veilStandard, startPoint: .top, endPoint: .bottom)
                .opacity(model.veilState == .standard ? 1 : 0)
            LinearGradient(stops: Self.veilLow, startPoint: .top, endPoint: .bottom)
                .opacity(model.veilState == .low ? 1 : 0)
        }
        .animation(.timingCurve(0.33, 0, 0.67, 1, duration: 0.64), value: model.veilState)
    }

    // Доли высоты полного окна (880). bg с нулевой альфой → рой виден; сплошной
    // bg → рой погашен. Совпадает с CSS-градиентами .ob-veil::before / ::after.
    private static let veilStandard: [Gradient.Stop] = [
        .init(color: OB.bg.opacity(0), location: 0),
        .init(color: OB.bg.opacity(0), location: 0.07),
        .init(color: OB.bg.opacity(0.80), location: 0.16),
        .init(color: OB.bg, location: 0.22),
        .init(color: OB.bg, location: 1),
    ]
    private static let veilLow: [Gradient.Stop] = [
        .init(color: OB.bg.opacity(0), location: 0),
        .init(color: OB.bg.opacity(0), location: 0.54),
        .init(color: OB.bg.opacity(0.80), location: 0.63),
        .init(color: OB.bg, location: 0.67),
        .init(color: OB.bg, location: 1),
    ]

    @ViewBuilder private var screen: some View {
        switch model.step {
        case 0: WelcomeScreen(onStart: { model.go(to: 1) })
        case 1: AgentScreen(model: model)
        case 2: ExtensionsScreen(model: model)
        case 3: SettingsScreen(model: model)
        case 4: PermissionsScreen(model: model)
        default: ReadyScreen(model: model)
        }
    }

    private var footer: some View {
        ZStack {
            OnboardingDots(count: model.stepCount, current: model.step,
                           onTap: { model.go(to: $0) })
                .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                SkipButton(action: onSkip)
            }
        }
        .opacity(model.bursting ? 0 : 1)
        .animation(OB.easeReal(0.15), value: model.bursting)
    }
}

/// Ловит ← / → на уровне окна (локальный NSEvent-монитор) и ведёт пагинацию
/// независимо от того, какой контрол держит фокус. Монитор снимается вместе с
/// мастером (dismantle). keyCode 123 = ←, 124 = →.
private struct KeyCatcher: NSViewRepresentable {
    let onLeft: () -> Void
    let onRight: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: onLeft(); return nil
            case 124: onRight(); return nil
            default: return event
            }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
        coordinator.monitor = nil
    }

    final class Coordinator { var monitor: Any? }
}

/// «Skip for now» — при наведении цвет третичный → вторичный (макет
/// `.ob-skip:hover`), увеличенная мишень по Фитсу за счёт паддинга.
private struct SkipButton: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text("Skip for now")
                .font(.system(size: 11))
                .foregroundStyle(hovering ? OB.tSecondary : OB.tTertiary)
                .padding(.vertical, 6).padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .animation(OB.easeReal(0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Конфигуратор окна

/// Приводит NSWindow к нужному виду: на онбординге — фиксированное портретное
/// окно 720×880 с прозрачным титлбаром «Foundry — Setup»; после — обычное
/// изменяемое окно «Foundry».
private struct WindowConfigurator: NSViewRepresentable {
    let onboarding: Bool

    final class Coordinator { var positioned = false }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        // окно у view появляется не сразу — ретраим, пока не поймаем реальный
        // NSWindow (иначе позиционирование ни разу не отрабатывает: в makeNSView
        // v.window ещё nil, а в updateNSView guard уже false).
        retryApply(view: v, coordinator: context.coordinator, tries: 0)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window, coordinator: context.coordinator) }
    }

    private func retryApply(view: NSView, coordinator: Coordinator, tries: Int) {
        DispatchQueue.main.async {
            if view.window != nil || tries > 20 {
                apply(to: view.window, coordinator: coordinator)
            } else {
                retryApply(view: view, coordinator: coordinator, tries: tries + 1)
            }
        }
    }

    private func apply(to window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.backgroundColor = NSColor(srgbRed: 5 / 255, green: 3 / 255, blue: 13 / 255, alpha: 1)
        // непрозрачное окно: под прозрачным титлбаром иначе просвечивает
        // вибрэнси-материал (в захвате читался как тёплая «полоса»/кайма сверху)
        window.isOpaque = true
        // тёмный титлбар как в макете (полоса #05030D под прозрачным баром), а не
        // светло-серый материал системы
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        // на онбординге не даём macOS восстанавливать сохранённый кадр —
        // окно всегда стартует top-center; после мастера главное окно снова
        // помнит свою позицию между запусками.
        window.isRestorable = !onboarding

        if onboarding {
            window.title = "Foundry — Setup"
            // свой титлбар рисуем в SwiftUI: прячем нативный титул и его волосину-
            // разделитель (это была «странная полоска» сверху), «светофор» остаётся
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            // Отвязать автосейв кадра: SwiftUI-WindowGroup вешает frameAutosaveName,
            // и macOS ВОССТАНАВЛИВАЕТ сохранённый кадр ПОСЛЕ нашего setFrame —
            // окно уезжало из центра туда, где стояло в прошлый раз (isRestorable
            // это не отменяет, это другой механизм). Пустое имя отключает автосейв,
            // и центрирование ниже держится.
            window.setFrameAutosaveName("")
            // размер — ПОЛНЫЙ кадр 720×880 (титлбар 44 внутри), как .ob-win в
            // макете. Не setContentSize: тот прибавлял 28px нативного бара. И не
            // 920 (прежняя ошибка): при 880 рабочая зона под титлбаром = 836 =
            // refHeight роя, значит KFIT ровно 1.0 — рой попадает в масштаб макета
            // (при 920 канвас 876 давал KFIT 0.954, рой выходил мельче).
            let size = NSSize(width: 720, height: 880)
            window.styleMask.remove(.resizable)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            if !coordinator.positioned {
                coordinator.positioned = true
                Self.centerTop(window, size: size)
                // WindowGroup докладывает свою каскадную позицию асинхронно ПОСЛЕ
                // нашего setFrame — окно уезжало влево-вверх. Пере-центрируем ещё
                // несколько раз с задержкой, пока раскладка не устаканится; после
                // окно в покое и его можно двигать.
                for delay in [0.05, 0.15, 0.35, 0.6] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        Self.centerTop(window, size: size)
                    }
                }
            } else if window.frame.size != size {
                // держим полный размер, не трогая позицию
                window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
            }
        } else {
            window.title = "Foundry"
            window.styleMask.insert(.resizable)
            window.standardWindowButton(.zoomButton)?.isEnabled = true
        }
    }

    /// Ставит окно по центру по горизонтали, прижав к верху рабочей зоны экрана.
    private static func centerTop(_ window: NSWindow, size: NSSize) {
        guard let screen = window.screen ?? NSScreen.main else {
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
            window.center()
            return
        }
        let vf = screen.visibleFrame
        let x = vf.minX + (vf.width - size.width) / 2
        let y = vf.maxY - size.height
        window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }
}
