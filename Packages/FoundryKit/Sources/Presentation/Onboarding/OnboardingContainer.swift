import AppKit
import SwiftUI

/// Корень приложения: при первом запуске показывает мастер онбординга поверх
/// главного окна, после разлёта уступает ему место. Флаг `didFinishOnboarding`
/// в AppStorage гейтит первый запуск.
public struct FoundryRootView: View {
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @State private var windowOpacity: Double = 1
    @State private var windowScale: CGFloat = 1

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
                .disabled(!didFinishOnboarding)
                .allowsHitTesting(didFinishOnboarding)

            if !didFinishOnboarding {
                OnboardingContainer(
                    onReveal: {
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.6)) {
                            windowOpacity = 0
                            windowScale = 0.985
                        }
                    },
                    onFinished: { didFinishOnboarding = true },
                    onSkip: { didFinishOnboarding = true }
                )
                .opacity(windowOpacity)
                .scaleEffect(windowScale)
                // Растянуть под титлбар на УРОВНЕ инстанса (не только внутри
                // контейнера): внутренний .ignoresSafeArea() контейнера сквозь
                // обёртки opacity/scaleEffect/transition под бар не пробивал —
                // верхние 28pt оставались непокрытыми, и туда проступал фон
                // ГЛАВНОГО окна (RunConsoleView, OB.bg #05030D) плоской «плашкой».
                // Здесь ignoresSafeArea тянет весь составной вид к y=0, как это и
                // так делает RunConsoleView-сосед → рой и WindowBackdrop доходят до
                // кромки, «плашки по цвету» больше нет.
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .background(WindowConfigurator(isOnboarding: !didFinishOnboarding))
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
            WindowBackdrop().ignoresSafeArea()

            // рой во всю высоту окна (кромка вида на y=0). Само облако опущено на
            // ~20pt в рендерере (heroDropPt), поэтому частицы не доходят до верхней
            // кромки; клип masksToBounds режет сверху пустой fon — линии среза нет.
            OnboardingSwarmView(
                isBursting: model.isBursting,
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
        .background(ArrowKeyMonitor(onLeft: { model.goPrevious() }, onRight: { model.goNext() }))
        .onAppear {
            model.onReveal = onReveal
            model.onFinished = onFinished
        }
    }

    /// Рабочая зона `.ob-stage` (flex:1) между роем и подвалом. ВСЕ экраны прижаты
    /// к низу: нижний элемент (кнопка / ряд карточек / панель) встаёт на ЕДИНОМ
    /// зазоре до пагинации — screenBottomPadding (эталон приветствия) + нижний s5=24.
    /// Верх у экранов разной высоты плавает (короткие садятся ниже, как приветствие) —
    /// якорь композиции у пагинации, а не у титульной кромки; так экраны не скачут.
    private var stageRegion: some View {
        VStack(spacing: 0) {
            screenContent
            Color.clear.frame(height: model.screenBottomPadding)
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
        // БЕЗ `.flattenWhileMoving`: drawingGroup на переходе растеризует контент
        // вместе со слоем теней, а тени собираются через preference (anchor-рамки),
        // который на входе нового экрана заполняется не за один кадр — drawingGroup
        // снимал бы кадры, где тени ещё не все встали → «тень появляется по частям».
        // Перф-довод за него отпал: блюров больше нет, тени дешёвые — переход
        // композитит нативно (CALayer), атомарно и гладко.
        FloatShadowLayer { screen }
            .frame(maxWidth: .infinity)
            .opacity(model.contentOpacity)
            .offset(y: model.contentOffset)
    }

    @ViewBuilder private var screen: some View {
        switch model.screen {
        case .welcome: WelcomeScreen(onStart: { model.go(to: .agents) })
        case .agents: AgentScreen(model: model)
        case .extensions: ExtensionsScreen(model: model)
        case .settings: SettingsScreen(model: model)
        case .permissions: PermissionsScreen(model: model)
        case .ready: ReadyScreen(model: model)
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
                count: model.stepCount, currentIndex: model.screen.rawValue,
                onTap: { if let target = OnboardingModel.Screen(rawValue: $0) { model.go(to: target) } }
            )
            .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                SkipButton(action: onSkip)
            }
            .offset(y: OnboardingDots.hitHeight / 2 - OnboardingDots.dotCenterFromBottom)
        }
        .frame(height: OnboardingDots.hitHeight)
        .opacity(model.isBursting ? 0 : 1)
        .animation(OB.easeReal(0.15), value: model.isBursting)
    }
}

/// Ловит ← / → на уровне окна (локальный NSEvent-монитор) и ведёт пагинацию
/// независимо от того, какой контрол держит фокус. Монитор снимается вместе с
/// мастером (dismantle).
private struct ArrowKeyMonitor: NSViewRepresentable {
    // Аппаратные keyCode стрелок (независимы от раскладки).
    private static let leftArrowKeyCode: UInt16 = 123
    private static let rightArrowKeyCode: UInt16 = 124

    let onLeft: () -> Void
    let onRight: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case Self.leftArrowKeyCode:
                onLeft()
                return nil
            case Self.rightArrowKeyCode:
                onRight()
                return nil
            default: return event
            }
        }
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    final class Coordinator { var monitor: Any? }
}

/// «Skip for now» — при наведении цвет третичный → вторичный (макет
/// `.ob-skip:hover`), увеличенная мишень по Фитсу за счёт паддинга.
private struct SkipButton: View {
    let action: () -> Void
    @State private var isHovering = false
    var body: some View {
        Button(action: action) {
            Text("Skip for now")
                .font(.system(size: 11))
                .foregroundStyle(isHovering ? OB.Text.secondary : OB.Text.tertiary)
                .padding(.vertical, 6).padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .animation(OB.hoverAnim(isHovering), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
