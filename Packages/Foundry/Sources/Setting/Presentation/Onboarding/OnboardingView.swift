import SwiftUI

/**
 Мастер первого запуска: рой на фоне рабочей зоны, экран поверх, подвал с точками и
 выходом. ЕДИНСТВЕННЫЙ публичный вид презентационного слоя BC `Setting` — мастер это
 не отдельный контекст, а пошаговый вид тех же настроек (позже к нему добавится окно
 настроек приложения). Внутренности (экраны, модель, рой) остаются закрытыми.

 Мастер ничего не решает про своё место в приложении: показать ли его поверх контента,
 каким сделать окно — забота корня композиции (`OnboardingGateView` в `Bootstrap`).
 Отсюда наружу торчат лишь три исхода: раскрытие главного окна на середине разлёта,
 конец разлёта и досрочный выход.
 */
public struct OnboardingView: View {
    private let onReveal: () -> Void
    private let onFinished: () -> Void
    private let onSkip: () -> Void

    @State private var model = OnboardingModel()

    public init(
        onReveal: @escaping () -> Void,
        onFinished: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.onReveal = onReveal
        self.onFinished = onFinished
        self.onSkip = onSkip
    }

    public var body: some View {
        ZStack(alignment: .top) {
            WindowBackdrop().ignoresSafeArea()

            // рой во всю высоту окна (кромка вида на y=0). Само облако опущено на
            // ~20pt в рендерере (heroDropPt), поэтому частицы не доходят до верхней
            // кромки; клип masksToBounds режет сверху пустой fon — линии среза нет.
            OnboardingSwarmView(
                isBursting: model.isBursting,
                onBurstProgress: { progress in model.burstProgress(progress) }
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
                onTap: { index in
                    if let target = OnboardingModel.Screen(rawValue: index) { model.go(to: target) }
                }
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
