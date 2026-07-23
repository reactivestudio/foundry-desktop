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
            // главное окно всегда под мастером — разлёт открывает его. Пока идёт
            // онбординг, консоль ПОЛНОСТЬЮ инертна: её TextEditor промпта —
            // нативный NSTextView со своим I-beam-курсором на уровне AppKit, и
            // z-порядок SwiftUI его не перебивает. Сквозь прозрачные зоны мастера
            // этот курсор проступал над точками пагинации («поле ввода»), и ни
            // ховер, ни палец до ряда не доходили. disabled+allowsHitTesting(false)
            // убирают консоль из событий и разрешения курсора на время мастера.
            RunConsoleView()
                .environment(store)
                .disabled(!done)
                .allowsHitTesting(done)

            if !done {
                OnboardingContainer(
                    onReveal: {
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.6)) {
                            winOpacity = 0
                            winScale = 0.985
                        }
                    },
                    onFinished: { done = true },
                    onSkip: { done = true }
                )
                .opacity(winOpacity)
                .scaleEffect(winScale)
                // Растянуть под титлбар на УРОВНЕ инстанса (не только внутри
                // контейнера): внутренний .ignoresSafeArea() контейнера сквозь
                // обёртки opacity/scaleEffect/transition под бар не пробивал —
                // верхние 28pt оставались непокрытыми, и туда проступал фон
                // ГЛАВНОГО окна (RunConsoleView, OB.bg #05030D) плоской «плашкой».
                // Здесь ignoresSafeArea тянет весь составной вид к y=0, как это и
                // так делает RunConsoleView-сосед → рой и FonBackground доходят до
                // кромки, «плашки по цвету» больше нет.
                .ignoresSafeArea()
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

    var body: some View {
        ZStack(alignment: .top) {
            FonBackground().ignoresSafeArea()

            // рой во всю высоту окна (кромка вида на y=0). Само облако опущено на
            // ~20pt в рендерере (heroDropPt), поэтому частицы не доходят до верхней
            // кромки; клип masksToBounds режет сверху пустой fon — линии среза нет.
            OnboardingSwarmView(
                bursting: model.bursting,
                onBurstProgress: { model.burstProgress($0) }
            )
            .ignoresSafeArea()

            // Завесы больше нет: рой заземляют сами карточки и панели — каждая
            // сидит в собственной парящей тени (единый слой под всеми телами:
            // CardShadowRow под рядом карточек, floatShadow под панелью), а не под
            // сплошным градиентом во всю ширину. Заголовки живут прямо на рое со
            // своим тёмным ореолом, как на приветствии.

            // контент: ob-stage (flex:1) между титлбаром и подвалом + подвал.
            // Верх/низ экрана — по макету: приветствие/Agent/Готово к низу
            // (flex-end), рабочие экраны к верху (padding-top 130).
            VStack(spacing: 0) {
                stageRegion
                // Подвал БЕЗ нижнего отступа: мишень точек тянется до самой нижней
                // кромки окна («область под кружками до самого низа»). Видимая точка
                // стоит на прежней высоте — её держит bottomPad внутри ряда.
                footer
                    .padding(.horizontal, 24)
            }
            // Верхней плашки нет вовсе: по просьбе — только нативный «светофор»
            // плавает над роем, никакого бара и подписи «Foundry — Setup».
        }
        // окно жёстко 720×880 (ставит WindowConfigurator); содержимое заполняет
        // весь кадр, включая титлбар (fullSizeContentView)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        // Скругление окна — в SwiftUI (окно прозрачное). Углы контента прозрачны →
        // видно скруглённое окно. «Светофор» — вне контента, не обрезается.
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // пагинация с клавиатуры: ← назад, → вперёд (монитор надёжнее onKeyPress,
        // которому нужен фокус — его перехватывает кнопка экрана)
        .background(KeyCatcher(onLeft: { model.goPrev() }, onRight: { model.goNext() }))
        .onAppear {
            model.onReveal = onReveal
            model.onFinished = onFinished
        }
    }

    /// Рабочая зона `.ob-stage` (flex:1) между роем и подвалом. ВСЕ экраны прижаты
    /// к низу: нижний элемент (кнопка / ряд карточек / панель) встаёт на ЕДИНОМ
    /// зазоре до пагинации — screenPadBottom (эталон приветствия) + нижний s5=24.
    /// Верх у экранов разной высоты плавает (короткие садятся ниже, как приветствие) —
    /// якорь композиции у пагинации, а не у титульной кромки; так экраны не скачут.
    private var stageRegion: some View {
        VStack(spacing: 0) {
            screenContent
            Color.clear.frame(height: model.screenPadBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 24)  // .ob-stage боковой s5
        .padding(.bottom, 24)  // .ob-stage нижний s5
    }

    /// Экран с анимацией входа/выхода (двухтактный переход): гашение прозрачности
    /// и доезд снизу на 22px; на время движения контент запекается в текстуру.
    private var screenContent: some View {
        // FloatShadowLayer собирает рамки всех карточек/панелей экрана и рисует их
        // тени ОДНИМ слоем под всем контентом (заголовки, тексты, кнопки — выше).
        //
        // БЕЗ `.flattenWhileMoving`: drawingGroup на переходе растеризовал контент
        // вместе со слоем теней, а тени собираются через preference (anchor-рамки),
        // который на входе нового экрана заполняется не за один кадр — drawingGroup
        // снимал кадры, где тени ещё не все встали → «тень появлялась по частям».
        // Раньше он был нужен ради перфа (9 блюров/кадр); блюра больше нет, тени
        // дешёвые — переход композитит нативно (CALayer), атомарно и гладко.
        FloatShadowLayer { screen }
            .frame(maxWidth: .infinity)
            .opacity(model.contentOpacity)
            .offset(y: model.contentOffset)
    }

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
        // Точки и Skip — на ОДНОЙ линии. Обе в полосе высотой hitHeight (низ полосы =
        // нижняя кромка окна). Точки внутри своей мишени сидят у низа (центр на
        // dotCenterFromBottom от низа), а Skip центрируется в полосе и смещается вниз
        // ровно на разницу «центр полосы − центр точки» — так его вертикальный центр
        // ложится точно на линию точек, а не висит выше. Значение считается из
        // геометрии ряда (не магическое число), поэтому не разъедется при правках.
        ZStack {
            OnboardingDots(
                count: model.stepCount, current: model.step,
                onTap: { model.go(to: $0) }
            )
            .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                SkipButton(action: onSkip)
            }
            .offset(y: OnboardingDots.hitHeight / 2 - OnboardingDots.dotCenterFromBottom)
        }
        .frame(height: OnboardingDots.hitHeight)
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
            case 123:
                onLeft()
                return nil
            case 124:
                onRight()
                return nil
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
        .animation(OB.hoverAnim(hovering), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Конфигуратор окна

/// Приводит NSWindow к нужному виду: на онбординге — фиксированное портретное
/// окно 720×880 с прозрачным титлбаром «Foundry — Setup»; после — обычное
/// изменяемое окно «Foundry».
private struct WindowConfigurator: NSViewRepresentable {
    let onboarding: Bool

    final class Coordinator {
        var positioned = false
        // Наблюдатели за сменой фокуса окна: AppKit на resign-key перекрашивает
        // титлбар системным серым и возвращает непрозрачный фон — переустанавливаем
        // безрамочный конфиг на каждое такое событие, иначе «сначала норм, потом серо».
        var chromeObservers: [NSObjectProtocol] = []
        // Поколение конфигурации: растёт на каждый apply. Отложенные такты
        // (enforceChrome и centerTop) сверяют своё поколение с текущим и молчат,
        // если оно устарело. Без этого Skip ломал главное окно: `done` переключается
        // мгновенно, а такты, заказанные ещё мастером, догоняли уже обычное окно и
        // возвращали ему безрамочный вид и размер 720×880.
        var generation = 0
        // Имя автосейва кадра, которое повесил SwiftUI. Мастер его снимает (иначе
        // macOS восстанавливает старый кадр ПОСЛЕ центрирования) — возвращаем при
        // выходе, чтобы главное окно снова помнило позицию.
        var savedAutosaveName: NSWindow.FrameAutosaveName?
        deinit {
            for observer in chromeObservers { NotificationCenter.default.removeObserver(observer) }
        }
    }
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
        // Новая конфигурация обесценивает все отложенные такты прежней.
        coordinator.generation &+= 1
        let generation = coordinator.generation
        // тёмный титлбар как в макете (а не светло-серый материал системы)
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
            // Безрамочный вид держим ПОСТОЯННО (см. enforceChrome): фон окна
            // прозрачный + скруглённый и клиппированный рамочный вид (NSThemeFrame),
            // чтобы срезать системную рамку и её углы. Один вызов не держится:
            // на resign-key AppKit перекрашивает титлбар серым и возвращает
            // непрозрачный фон — потому переустанавливаем на каждую смену фокуса.
            Self.enforceChrome(window)
            // Первый enforceChrome часто отрабатывает ДО того, как SwiftUI/AppKit
            // достроят подвиды титлбара (серый материал, `_NSTitlebarDecorationView`,
            // сам заголовок) — тогда прятать нечего, и «серая плашка с подписью и
            // бордером» остаётся, а смены фокуса, чтобы переустановить, не случается
            // (окно рождается ключевым). Догоняем несколькими отложенными тактами —
            // как с центрированием: к 0.6с подвиды точно на месте и гасятся.
            for delay in [0.05, 0.15, 0.35, 0.6, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard coordinator.generation == generation else { return }
                    Self.enforceChrome(window)
                }
            }
            if coordinator.chromeObservers.isEmpty {
                let names: [Notification.Name] = [
                    NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                    NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
                ]
                for name in names {
                    let obs = NotificationCenter.default.addObserver(
                        forName: name, object: window, queue: .main
                    ) { [weak window] _ in
                        MainActor.assumeIsolated {
                            guard let window else { return }
                            Self.enforceChrome(window)
                        }
                    }
                    coordinator.chromeObservers.append(obs)
                }
            }
            // Отвязать автосейв кадра: SwiftUI-WindowGroup вешает frameAutosaveName,
            // и macOS ВОССТАНАВЛИВАЕТ сохранённый кадр ПОСЛЕ нашего setFrame —
            // окно уезжало из центра туда, где стояло в прошлый раз (isRestorable
            // это не отменяет, это другой механизм). Пустое имя отключает автосейв,
            // и центрирование ниже держится.
            if coordinator.savedAutosaveName == nil {
                coordinator.savedAutosaveName = window.frameAutosaveName
            }
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
                        guard coordinator.generation == generation else { return }
                        Self.centerTop(window, size: size)
                    }
                }
            } else if window.frame.size != size {
                // держим полный размер, не трогая позицию
                window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
            }
        } else {
            // обычное окно: снимаем наблюдателей и разворачиваем ВЕСЬ безрамочный
            // вид обратно (см. restoreChrome — зеркало enforceChrome).
            for observer in coordinator.chromeObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            coordinator.chromeObservers.removeAll()
            Self.restoreChrome(window)
            if let saved = coordinator.savedAutosaveName {
                window.setFrameAutosaveName(saved)
                coordinator.savedAutosaveName = nil
            }
            window.title = "Foundry"
            window.styleMask.insert(.resizable)
            window.standardWindowButton(.zoomButton)?.isEnabled = true
        }
    }

    /// Переустанавливаемый безрамочный вид окна онбординга. Зовётся при первичной
    /// настройке и на каждую смену фокуса — иначе AppKit на resign-key вернёт
    /// системный серый титлбар и непрозрачный фон, а рамка проступит обратно.
    @MainActor private static func enforceChrome(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        // БЕЗ БОРДЕРА: на этой macOS родной 1px-бордер titled-окна снимается только
        // вместе с тенью — они один механизм. Делаем окно прозрачным и выключаем
        // тень: сервер больше не обводит силуэт светлым кантом. Скругление углов —
        // в SwiftUI (.clipShape). Цена — нет родной тени (её при желании рисуем сами).
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // NSThemeFrame не клиппируем (даёт кант-артефакт). Гасим хром титлбара:
        // серый материал и линию-накладку — «светофор» (NSButton) остаётся.
        if let frameView = window.contentView?.superview {
            frameView.layer?.cornerRadius = 0
            frameView.layer?.masksToBounds = false
            frameView.layer?.borderWidth = 0
            setTitlebarChromeHidden(true, in: frameView)
        }
    }

    /// Возврат обычного вида — ЗЕРКАЛО `enforceChrome`. Мастер и главное окно это
    /// один и тот же NSWindow (`WindowConfigurator` висит на корне, `onboarding`
    /// переключается на ходу), поэтому всё выключенное надо включить обратно: иначе
    /// после Skip или финала главное окно до перезапуска оставалось без тени, без
    /// заголовка и с погашенным хромом титлбара. Правило: любое поле, которое трогает
    /// `enforceChrome`, обязано иметь строку здесь — кроме `appearance` и
    /// `titlebarAppearsTransparent`, они одинаковы для ОБОИХ режимов и ставятся выше,
    /// в общей части `apply`; возвращать тут нечего.
    @MainActor private static func restoreChrome(_ window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = NSColor(srgbRed: 14 / 255, green: 11 / 255, blue: 20 / 255, alpha: 1)
        window.hasShadow = true
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .automatic
        for view in [window.contentView, window.contentView?.superview] {
            view?.layer?.cornerRadius = 0
            view?.layer?.masksToBounds = false
        }
        if let frameView = window.contentView?.superview {
            setTitlebarChromeHidden(false, in: frameView)
        }
    }

    /// Гасит или возвращает хром титлбара: системный материал (`NSVisualEffectView`,
    /// серый на неактивном окне) и декоративную накладку (`_NSTitlebarDecorationView` —
    /// это линия-разделитель под баром). Кнопки-«светофор» (`NSButton` в
    /// `NSTitlebarView`) не трогаем — остаются видимыми и рабочими. Один обход на оба
    /// направления: так набор классов не разъедется между «спрятать» и «вернуть».
    @MainActor private static func setTitlebarChromeHidden(_ hidden: Bool, in frameView: NSView) {
        func walk(_ view: NSView, underTitlebar: Bool) {
            let cls = String(describing: type(of: view))
            let isTitlebar = underTitlebar || cls == "NSTitlebarContainerView"
            if isTitlebar, view is NSVisualEffectView || cls == "_NSTitlebarDecorationView" {
                view.isHidden = hidden
            }
            for sub in view.subviews { walk(sub, underTitlebar: isTitlebar) }
        }
        walk(frameView, underTitlebar: false)
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
