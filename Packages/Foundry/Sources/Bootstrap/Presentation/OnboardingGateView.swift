import Setting
import SwiftUI

/**
 Гейт первого запуска — сшивка контекстов, а не часть мастера: решает, что показать
 поверх контента приложения, пока не пройдена первичная настройка, и каким сделать окно
 (`WindowConfigurator`). Потому и живёт в корне композиции: мастер (`OnboardingView` из
 презентационного слоя BC `Setting`) про Run-консоль и про окно не знает вовсе, а
 контент-под-мастером инъектируется сюда сверху (`@ViewBuilder mainContent`).

 Признак «мастер пройден» — обычная durable-настройка (`Preference`, группа `Setup`),
 читается из стора настроек. Прежний `@AppStorage("didFinishOnboarding")` жил прямо во
 вью, то есть хранилище пробивало слои; теперь путь один и тот же для всех настроек.
 */
struct OnboardingGateView<MainContent: View>: View {
    @State private var windowOpacity: Double = 1
    @State private var windowScale: CGFloat = 1

    private let preferenceStore: PreferenceStore
    private let mainContent: MainContent

    init(preferenceStore: PreferenceStore, @ViewBuilder mainContent: () -> MainContent) {
        self.preferenceStore = preferenceStore
        self.mainContent = mainContent()
    }

    /// Пройдена ли первичная настройка — гейт спрашивает это у настроек, а не у себя.
    private var didFinishOnboarding: Bool { preferenceStore.setup.isFinished }

    var body: some View {
        ZStack {
            // контент приложения всегда под мастером — разлёт открывает его. Пока
            // идёт онбординг, он ПОЛНОСТЬЮ инертен: TextEditor промпта консоли —
            // нативный NSTextView со своим I-beam-курсором на уровне AppKit, и
            // z-порядок SwiftUI его не перебивает. Сквозь прозрачные зоны мастера
            // этот курсор проступал над точками пагинации («поле ввода»), и ни
            // ховер, ни палец до ряда не доходили. disabled+allowsHitTesting(false)
            // убирают контент из событий и разрешения курсора на время мастера.
            mainContent
                .disabled(!didFinishOnboarding)
                .allowsHitTesting(didFinishOnboarding)

            if !didFinishOnboarding {
                OnboardingView(
                    onReveal: {
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.6)) {
                            windowOpacity = 0
                            windowScale = 0.985
                        }
                    },
                    onFinished: { preferenceStore.finishSetup() },
                    onSkip: { preferenceStore.finishSetup() }
                )
                .opacity(windowOpacity)
                .scaleEffect(windowScale)
                // Растянуть под титлбар на УРОВНЕ инстанса (не только внутри
                // мастера): внутренний .ignoresSafeArea() под обёртками
                // opacity/scaleEffect/transition под бар не пробивал — верхние 28pt
                // оставались непокрытыми, и туда проступал фон ГЛАВНОГО окна
                // (RunConsoleView, OB.bg #05030D) плоской «плашкой». Здесь
                // ignoresSafeArea тянет весь составной вид к y=0, как это и так
                // делает RunConsoleView-сосед → рой и фон доходят до кромки,
                // «плашки по цвету» больше нет.
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .background(WindowConfigurator(isOnboarding: !didFinishOnboarding))
    }
}
