import Foundation

/// Планировщик отложенной работы на главном акторе. Онбординг задерживает шаги
/// имитации установки (Install → пауза → ✓ → пауза → следующий экран); задержки
/// зашиты числами в секундах, как в принятом прототипе.
///
/// Вынесен в порт (practices 03: сервисы — через init) ради тестируемости:
/// продакшн-реализация — тот же `DispatchQueue.main.asyncAfter`, тайминги не
/// меняются ни на долю; тест подставляет ручной планировщик и прокручивает
/// задержки детерминированно, не ожидая реального времени.
@MainActor
protocol OnboardingScheduler {
    /// Выполнить `work` на главном акторе через `seconds` секунд.
    func schedule(after seconds: Double, _ work: @escaping @MainActor () -> Void)
}

/// Продакшн-планировщик: буквально `DispatchQueue.main.asyncAfter(deadline:)` —
/// поведение и тайминги те же, что были до вынесения в порт.
struct MainQueueOnboardingScheduler: OnboardingScheduler {
    func schedule(after seconds: Double, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { work() }
        }
    }
}
