import Testing

@testable import Setting

/// Ручной планировщик: копит отложенную работу вместо GCD и прокручивает её
/// синхронно. Так имитацию установки (с задержками 0.9/0.55с) можно проверить
/// детерминированно, не ожидая реального времени. Вложенные задержки, заказанные
/// уже во время прокрутки, тоже выполняются — `drain` идёт по растущему списку.
@MainActor
final class ManualOnboardingScheduler: OnboardingScheduler {
    private var pending: [@MainActor () -> Void] = []
    private(set) var scheduledCount = 0

    func schedule(after seconds: Double, _ work: @escaping @MainActor () -> Void) {
        scheduledCount += 1
        pending.append(work)
    }

    /// Выполнить всю накопленную работу в порядке постановки, включая вложенную.
    func drain() {
        var i = 0
        while i < pending.count {
            let work = pending[i]
            i += 1
            work()
        }
        pending.removeAll()
    }
}

@MainActor
@Suite("Модель онбординга")
struct OnboardingModelTests {

    // ── Навигация ────────────────────────────────────────────────────────────

    @Test("Старт с приветствия, шесть экранов")
    func initialState() {
        let model = OnboardingModel(scheduler: ManualOnboardingScheduler())
        #expect(model.screen == .welcome)
        #expect(model.stepCount == 6)
        #expect(model.navigationTarget == .welcome)
        #expect(!model.isBursting)
    }

    @Test("Два сжатых нажатия вперёд дают честный +2, а не +1")
    func rapidNextAdvancesHonestly() {
        let model = OnboardingModel(scheduler: ManualOnboardingScheduler())
        // Первое нажатие наметило agents и запустило переход (screen ещё welcome).
        model.goNext()
        #expect(model.navigationTarget == .agents)
        // Второе нажатие в разгар перехода считает от намеченной цели, не от screen,
        // — иначе оба целили бы в agents. Теперь честно extensions.
        model.goNext()
        #expect(model.navigationTarget == .extensions)
    }

    @Test("Назад не уходит за первый экран, вперёд — за последний")
    func navigationClampsAtEnds() {
        let model = OnboardingModel(scheduler: ManualOnboardingScheduler())
        model.goPrevious()
        #expect(model.navigationTarget == .welcome)  // с первого назад некуда
        model.go(to: .ready)
        #expect(model.navigationTarget == .ready)
        model.goNext()
        #expect(model.navigationTarget == .ready)  // с последнего вперёд некуда
    }

    // ── Исходы экранов инструментов ───────────────────────────────────────────

    // Имитации установки больше нет: установленность приходит из системы (`ToolStore`),
    // а мастер знает лишь, куда идти после исхода экрана.

    @Test("Выбранный агент уводит на экран расширений")
    func chosenAgentAdvancesToExtensions() {
        let model = OnboardingModel(scheduler: ManualOnboardingScheduler())
        model.go(to: .agents)

        model.agentChosen()

        #expect(model.navigationTarget == .extensions)
    }

    @Test("Готовые расширения уводят к настройкам")
    func readyExtensionsAdvanceToSettings() {
        let model = OnboardingModel(scheduler: ManualOnboardingScheduler())
        model.go(to: .extensions)

        model.extensionsReady()

        #expect(model.navigationTarget == .settings)
    }

    // ── Разрешения ────────────────────────────────────────────────────────────

    // Ни тумблеров настроек, ни статусов разрешений у модели мастера больше нет: первые
    // сидят на агрегате через `PreferenceStore`, вторые — на ОС через `PermissionStore`
    // (их поведение проверяют `PreferenceStoreTests` и `PermissionStoreTests`). Мастеру
    // осталась реакция на исход.

    @Test("Когда система выдала все разрешения — переход к финалу")
    func grantedPermissionsAdvanceToReady() {
        let scheduler = ManualOnboardingScheduler()
        let model = OnboardingModel(scheduler: scheduler)
        model.go(to: .permissions)

        model.permissionsGranted()
        #expect(model.navigationTarget == .permissions)  // пауза на «✓ Granted» ещё идёт

        scheduler.drain()
        #expect(model.navigationTarget == .ready)
    }

    // ── Финал и разлёт ────────────────────────────────────────────────────────

    @Test("finish запускает разлёт один раз")
    func finishStartsBurstOnce() {
        let model = OnboardingModel(scheduler: ManualOnboardingScheduler())
        model.finish()
        #expect(model.isBursting)
        #expect(model.contentOpacity == 0)  // stage гаснет
    }

    @Test("Прогресс разлёта зовёт reveal на половине и finish в конце, по разу")
    func burstProgressFiresCallbacksOnce() {
        let model = OnboardingModel(scheduler: ManualOnboardingScheduler())
        var reveals = 0
        var finishes = 0
        model.onReveal = { reveals += 1 }
        model.onFinished = { finishes += 1 }

        model.burstProgress(0.2)
        #expect(reveals == 0 && finishes == 0)  // рано
        model.burstProgress(0.55)
        model.burstProgress(0.7)
        #expect(reveals == 1)  // reveal ровно один раз на пороге 0.55
        model.burstProgress(0.999)
        model.burstProgress(1.0)
        #expect(finishes == 1)  // finish ровно один раз в конце
    }
}
