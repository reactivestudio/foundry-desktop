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
    private let permissionStore: PermissionStore
    private let toolStore: ToolStore
    private let mainContent: MainContent

    init(
        preferenceStore: PreferenceStore,
        permissionStore: PermissionStore,
        toolStore: ToolStore,
        @ViewBuilder mainContent: () -> MainContent
    ) {
        self.preferenceStore = preferenceStore
        self.permissionStore = permissionStore
        self.toolStore = toolStore
        self.mainContent = mainContent()
    }

    /// Мастер кончился в ЭТОМ сеансе. Durable-истина живёт в настройке (`Preference`,
    /// группа `Setup`) и её достаточно на следующем запуске — но SwiftUI она не будит:
    /// наблюдение за стором тут не срабатывает (проверено — `withObservationTracking`
    /// не зовёт `onChange` на `finishSetup`), и до перезапуска гейт оставался бы с
    /// мастером на экране, а окно — мастерским: 720×880, без полного экрана, с
    /// заголовком «Foundry — Setup». Поэтому исход мастера гейт запоминает и у себя.
    @State private var didFinishInSession = false

    /// Пройдена ли первичная настройка. Двумя источниками: свежий исход этого сеанса
    /// и durable-настройка — гейт спрашивает её у настроек, а не заводит своё
    /// хранилище.
    private var didFinishOnboarding: Bool {
        didFinishInSession || preferenceStore.setup.isFinished
    }

    /// Оба исхода мастера — конец и досрочный выход — ведут к одному: настройка
    /// помечается пройденной, и гейт уходит с экрана вместе с мастерским окном.
    private func finishOnboarding() {
        preferenceStore.finishSetup()
        didFinishInSession = true
    }

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
                    preference: preferenceStore,
                    permission: permissionStore,
                    tool: toolStore,
                    onReveal: {
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.6)) {
                            windowOpacity = 0
                            windowScale = 0.985
                        }
                    },
                    onFinished: { finishOnboarding() },
                    onSkip: { finishOnboarding() }
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
        // Второй аргумент — не дубль первого: `isOnboarding` это состояние ЭТОГО
        // обновления вида, а замыкание спрашивает настройку в момент вызова. Долгие
        // наблюдатели окна живут дольше обновлений и обязаны знать факт, а не снимок.
        .background(
            WindowConfigurator(
                isOnboarding: !didFinishOnboarding,
                isOnboardingNow: { !preferenceStore.setup.isFinished }
            )
        )
    }
}
