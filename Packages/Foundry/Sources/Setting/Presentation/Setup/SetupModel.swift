import SwiftUI

/// Машина состояний мастера первого запуска: шесть экранов, двухтактные переходы,
/// финальный разлёт с передачей управления главному окну.
///
/// Состояния экранов у неё больше нет вовсе — ни настроек, ни разрешений, ни
/// установленности инструментов: всё это живёт в сторах BC `Setting` (`PreferenceStore`,
/// `PermissionStore`, `ToolStore`), то есть в агрегате и в самой системе. Мастеру
/// осталось ровно то, чем он и является: порядок экранов и реакция на их исходы.
@MainActor
@Observable
final class SetupModel {
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

    // Ни каталога карточек, ни установленности здесь нет: карточки собирают сами
    // экраны, а состояние установки приходит из `ToolStore` (порт к системе).

    // Настроек здесь нет намеренно: экран настроек сидит прямо на агрегате
    // `Preference` через `PreferenceStore` (см. `SettingsScreen`). Мастеру осталась
    // только навигация по ним — второго состояния тех же тумблеров не заводим.

    // Разрешений macOS здесь тоже нет: их состояние принадлежит системе и живёт в
    // `PermissionStore` (см. `PermissionsScreen`). Мастеру осталась реакция на исход —
    // `permissionsGranted()`.

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

    /// Пауза перед автопереходом (как в принятом прототипе): исход экрана должен
    /// успеть прочитаться — галочка «✓ Granted», выбранная карточка, — и только потом
    /// уезжает сам экран.
    private let advanceDelay: TimeInterval = 0.55

    /// Планировщик отложенных переходов. Дефолт — GCD (тайминги как были); тест
    /// подставляет ручной, чтобы прокрутить шаги детерминированно.
    private let scheduler: SetupScheduler

    init(scheduler: SetupScheduler = MainQueueSetupScheduler()) {
        self.scheduler = scheduler
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

    // MARK: - Исходы экранов

    /// Агент выбран — дальше к частям Foundry. Без паузы: карточка уже установлена,
    /// ждать нечего, и в прототипе клик по установленной вёл дальше сразу.
    func agentChosen() {
        go(to: .extensions)
    }

    /// Обе части на месте — дальше к настройкам.
    func extensionsReady() {
        go(to: .settings)
    }

    /// Система выдала все разрешения — уходим на финал тем же тактом, что и после
    /// установки карточки: короткая пауза, чтобы «✓ Granted» успел прочитаться, затем
    /// переход. Сам факт выдачи мастер не решает — о нём сообщает экран, спросивший ОС.
    func permissionsGranted() {
        scheduler.schedule(after: advanceDelay) { self.go(to: .ready) }
    }

    // MARK: - Финал

    func finish() {
        guard !isBursting else { return }
        isBursting = true
        withAnimation(SetupStyle.easeReal(0.15)) { contentOpacity = 0 }  // stage гаснет
    }

    /// Прогресс разлёта от SetupSwarmView.
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
