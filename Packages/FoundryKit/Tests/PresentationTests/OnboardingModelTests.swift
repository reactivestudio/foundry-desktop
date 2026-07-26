import Testing

@testable import Presentation

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

    // ── Имитация установки ────────────────────────────────────────────────────

    @Test("Установка агента: Installing… → ✓ → выбор → переход к расширениям")
    func agentInstallFlow() {
        let scheduler = ManualOnboardingScheduler()
        let model = OnboardingModel(scheduler: scheduler)
        let id = model.agents[1].id  // codex — не предустановлен

        model.tapAgent(id)
        #expect(model.installingAgent == id)  // сразу «Installing…»
        #expect(!model.installedAgents.contains(id))

        scheduler.drain()  // прокрутить обе задержки (0.9 → установлено, 0.55 → переход)
        #expect(model.installingAgent == nil)
        #expect(model.installedAgents.contains(id))
        #expect(model.selectedAgent == id)
        #expect(model.navigationTarget == .extensions)  // ушли на экран расширений
    }

    @Test("Повторный тап по установленному агенту не запускает установку заново")
    func tappingInstalledAgentJustSelects() {
        let scheduler = ManualOnboardingScheduler()
        let model = OnboardingModel(scheduler: scheduler)
        let id = model.agents[1].id
        model.tapAgent(id)
        scheduler.drain()
        let countAfterInstall = scheduler.scheduledCount

        model.tapAgent(id)  // уже установлен — только выбор + переход, без Installing
        #expect(model.installingAgent == nil)
        #expect(model.selectedAgent == id)
        #expect(scheduler.scheduledCount == countAfterInstall)  // новых задержек нет
    }

    @Test("Экран расширений уводит дальше только когда установлены все")
    func extensionsAdvanceOnlyWhenAllInstalled() {
        let scheduler = ManualOnboardingScheduler()
        let model = OnboardingModel(scheduler: scheduler)
        model.go(to: .extensions)

        model.tapExtension(model.extensions[0].id)
        scheduler.drain()
        #expect(model.installedExtensions.count == 1)
        #expect(model.navigationTarget == .extensions)  // ещё не все — стоим на месте

        model.tapExtension(model.extensions[1].id)
        scheduler.drain()
        #expect(model.installedExtensions.count == model.extensions.count)
        #expect(model.navigationTarget == .settings)  // все установлены — вперёд
    }

    // ── Настройки и разрешения ────────────────────────────────────────────────

    @Test("Тумблер настройки переключается")
    func toggleFlipsSetting() {
        let model = OnboardingModel(scheduler: ManualOnboardingScheduler())
        let id = model.settings[0].id
        let before = model.settings[0].isOn
        model.toggle(id)
        #expect(model.settings[0].isOn == !before)
    }

    @Test("Когда выданы все разрешения — переход к финалу")
    func grantingAllPermissionsAdvances() {
        let scheduler = ManualOnboardingScheduler()
        let model = OnboardingModel(scheduler: scheduler)
        model.go(to: .permissions)

        model.grant(model.permissions[0].id)
        #expect(model.permissions[0].isGranted)
        #expect(model.navigationTarget == .permissions)  // ещё не все

        model.grant(model.permissions[1].id)
        let allGranted = model.permissions.allSatisfy(\.isGranted)
        #expect(allGranted)
        scheduler.drain()
        #expect(model.navigationTarget == .ready)  // все выданы — на экран Ready
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
