import SwiftUI

/// Машина состояний мастера первого запуска: шесть экранов, двухтактные переходы,
/// имитация установки (Install → Installing… → ✓, как в принятом прототипе),
/// финальный разлёт с передачей управления главному окну.
///
/// Установки визуально имитируются — экран верен прототипу пиксель-в-пиксель;
/// реальные инсталляции агентов/расширений сюда не подключены.
@MainActor
@Observable
final class OnboardingModel {
    /// Экраны мастера в порядке прохождения. `rawValue` — позиция в пагинации:
    /// стрелки и точки навигируют по индексу, а автопереходы называют экран по
    /// имени (`go(to: .extensions)`), а не магическим числом.
    enum Screen: Int, CaseIterable {
        case welcome, agents, extensions, settings, permissions, ready
    }

    // текущий экран и анимация его входа/выхода (двухтактный переход)
    var screen: Screen = .welcome
    var contentOpacity: Double = 1
    var contentOffset: CGFloat = 0
    /// Идёт ли межэкранный переход. Служит защёлкой от наложения тактов: пока true,
    /// `go(to:)` не запускает новый такт, а лишь двигает `pendingTarget`, и текущий
    /// такт доедет до самой свежей цели.
    private(set) var isAnimating = false

    // агенты
    let agents: [InstallCardModel]
    var installedAgents: Set<String> = []
    var installingAgent: String?
    var selectedAgent: String?

    // расширения
    let extensions: [InstallCardModel]
    var installedExtensions: Set<String> = []
    var installingExtension: String?

    // настройки (сид — в OnboardingCatalog; здесь живёт лишь мутабельное состояние)
    var settings: [Setting]

    // разрешения macOS (сид — в OnboardingCatalog)
    var permissions: [Permission]

    // разлёт
    var isBursting = false
    private var didReveal = false
    private var didFinish = false

    /// Позвать раскрытие главного окна (разлёт перевалил за половину).
    var onReveal: () -> Void = {}
    /// Разлёт завершён — мастер можно снять.
    var onFinished: () -> Void = {}

    var stepCount: Int { Screen.allCases.count }

    // MARK: - Раскладка экрана (единый нижний зазор до пагинации)

    /// Единый нижний воздух экрана над пагинацией — эталон взят с приветствия (s6=32).
    /// ОДИН на все шесть экранов: этим и «фиксируется» композиция — нижний элемент
    /// любого экрана (кнопка / ряд карточек / панель) встаёт на равном расстоянии до
    /// точек, и расстояние не скачет от экрана к экрану.
    let screenBottomPadding: CGFloat = 32

    /// Тайминги имитации установки (как в принятом прототипе): пауза кнопки в
    /// состоянии Installing… до галочки, затем пауза с готовой галочкой до
    /// автоперехода на следующий экран.
    private let installDuration: TimeInterval = 0.9
    private let advanceDelay: TimeInterval = 0.55

    /// Планировщик задержек имитации установки. Дефолт — GCD (тайминги как были);
    /// тест подставляет ручной, чтобы прокрутить шаги детерминированно.
    private let scheduler: OnboardingScheduler

    init(scheduler: OnboardingScheduler = MainQueueOnboardingScheduler()) {
        self.scheduler = scheduler
        agents = OnboardingCatalog.agents
        extensions = OnboardingCatalog.extensions
        settings = OnboardingCatalog.settings
        permissions = OnboardingCatalog.permissions
    }

    // MARK: - Переходы (двухтактные: уход 300ms → свап → вход 640ms; плавно, без рывка)

    // Куда переход держит курс. Быстрые нажатия НЕ плодят отдельные анимации и не
    // снимаются рывком «в лоб» — они лишь двигают эту цель; текущий такт на своём
    // стыке доедет сразу до самого свежего адреса. Так три быстрых стрелки = один
    // плавный переход к финальному экрану, без мельтешения гашений.
    private var pendingTarget: Screen?

    /// Куда сейчас держит курс навигация: намеченная цель, а в покое — текущий
    /// экран. Только чтение (диагностика и тесты): подтверждает «честный +2» при
    /// сжатых нажатиях, не открывая наружу мутабельность `pendingTarget`.
    var navigationTarget: Screen { pendingTarget ?? screen }

    func go(to next: Screen) {
        guard next != screen, !isBursting else { return }
        pendingTarget = next
        if !isAnimating { startTransition() }
    }

    /// Один такт перехода: увести текущий экран (гашение + лёгкий подъём) → на
    /// стыке свапнуть на САМУЮ свежую цель (сжатые быстрые нажатия) → ввести новый.
    /// Хвостом проверяем, не накопились ли ещё нажатия за время ввода — тогда
    /// плавно продолжаем следующим тактом (без стыка кадров и рывка).
    private func startTransition() {
        guard let target = pendingTarget, target != screen else {
            pendingTarget = nil
            isAnimating = false
            return
        }
        isAnimating = true
        // Уход: плавная кривая (разгон И затухание, control2 не в углу) — контент не
        // обрывается на полной скорости, а мягко тает, поднимаясь. Дольше прежнего.
        withAnimation(.timingCurve(0.35, 0, 0.35, 1, duration: 0.30)) {
            contentOpacity = 0
            contentOffset = -12
        } completion: { [self] in
            let destination = pendingTarget ?? target
            pendingTarget = nil
            screen = destination
            contentOffset = 14
            // Вход: длинный дом-decel (0.2,0,0,1) — новый экран мягко доезжает снизу
            // и проявляется, без рывка на старте.
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.64)) {
                contentOpacity = 1
                contentOffset = 0
            } completion: { [self] in
                if let pending = pendingTarget, pending != screen {
                    startTransition()  // за время ввода докрутили ещё — продолжаем гладко
                } else {
                    pendingTarget = nil
                    isAnimating = false
                }
            }
        }
    }

    /// Навигация стрелками (как клик по точкам пагинации): вправо — дальше,
    /// влево — назад, в пределах ряда экранов (края отсекает `Screen(rawValue:)`).
    ///
    /// Считаем от УЖЕ намеченной цели (`pendingTarget`), а не от `screen` — тот в
    /// разгар перехода ещё не сдвинулся, и два быстрых нажатия иначе целили бы в
    /// один и тот же экран (+1, +1). Теперь второе нажатие честно даёт +2.
    func goNext() {
        let base = pendingTarget ?? screen
        if let next = Screen(rawValue: base.rawValue + 1) { go(to: next) }
    }
    func goPrevious() {
        let base = pendingTarget ?? screen
        if let previous = Screen(rawValue: base.rawValue - 1) { go(to: previous) }
    }

    // MARK: - Карточки

    func tapAgent(_ id: String) {
        if installedAgents.contains(id) {
            selectedAgent = id
            go(to: .extensions)
            return
        }
        simulateInstall(id, installing: \.installingAgent, installed: \.installedAgents) { [self] in
            selectedAgent = id
            scheduler.schedule(after: advanceDelay) { self.go(to: .extensions) }
        }
    }

    func tapExtension(_ id: String) {
        if installedExtensions.contains(id) {
            if installedExtensions.count == extensions.count { go(to: .settings) }
            return
        }
        simulateInstall(id, installing: \.installingExtension, installed: \.installedExtensions) { [self] in
            if installedExtensions.count == extensions.count {
                scheduler.schedule(after: advanceDelay) { self.go(to: .settings) }
            }
        }
    }

    /// Общий каркас имитации установки карточки (как в принятом прототипе):
    /// защёлка от повторного тапа во время установки → флаг Installing… → пауза →
    /// снять флаг, пометить установленным → `onInstalled`. Различия агентов и
    /// расширений (повторный тап уже установленной, выбор, условие автоперехода)
    /// остаются явными у вызывающего; здесь — ровно общий протокол установки.
    private func simulateInstall(
        _ id: String,
        installing installingKeyPath: ReferenceWritableKeyPath<OnboardingModel, String?>,
        installed installedKeyPath: ReferenceWritableKeyPath<OnboardingModel, Set<String>>,
        onInstalled: @escaping () -> Void
    ) {
        guard self[keyPath: installingKeyPath] == nil else { return }
        self[keyPath: installingKeyPath] = id
        scheduler.schedule(after: installDuration) { [self] in
            self[keyPath: installingKeyPath] = nil
            self[keyPath: installedKeyPath].insert(id)
            onInstalled()
        }
    }

    func toggle(_ id: String) {
        guard let index = settings.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(OB.easeReal(0.30)) { settings[index].isOn.toggle() }
    }

    func grant(_ id: String) {
        guard let index = permissions.firstIndex(where: { $0.id == id }) else { return }
        permissions[index].isGranted = true
        if permissions.allSatisfy(\.isGranted) {
            scheduler.schedule(after: advanceDelay) { self.go(to: .ready) }
        }
    }

    // MARK: - Финал

    func finish() {
        guard !isBursting else { return }
        isBursting = true
        withAnimation(OB.easeReal(0.15)) { contentOpacity = 0 }  // stage гаснет
    }

    /// Прогресс разлёта от OnboardingSwarmView.
    func burstProgress(_ progress: Double) {
        if progress >= 0.55 && !didReveal {
            didReveal = true
            onReveal()
        }
        if progress >= 0.999 && !didFinish {
            didFinish = true
            onFinished()
        }
    }
}
