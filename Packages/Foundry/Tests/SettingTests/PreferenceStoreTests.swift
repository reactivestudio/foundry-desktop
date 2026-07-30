import Testing

@testable import Setting

/// `PreferenceStore` — тонкий контроллер презентации: стартует со снимка настроек,
/// а интент проводит через сценарий (в хранилище) и обновляет собственное чтение.
/// Оба вида BC (мастер и будущее окно настроек) видят его одинаково.
@Suite("PreferenceStore")
@MainActor
struct PreferenceStoreTests {

    private func makeStore(
        repository: InMemoryPreferenceRepository = InMemoryPreferenceRepository()
    ) -> PreferenceStore {
        PreferenceStore(service: PreferenceService(repository: repository))
    }

    @Test("Стартует с сохранённого набора, а не с дефолта")
    func startsFromStoredPreference() {
        let repository = InMemoryPreferenceRepository()
        let stored = Preference.of()
        stored.change(theme: .dark)
        repository.save(entity: stored)

        let store = makeStore(repository: repository)

        #expect(store.appearance.theme == .dark)
    }

    @Test("Нет сохранённого набора — стор показывает доменные дефолты")
    func fallsBackToDomainDefaults() {
        let store = makeStore()

        #expect(store.appearance.theme == .system)
        #expect(store.general.tokensInKeychain)
    }

    @Test("Гейт первого запуска: стор отдаёт признак настройки и закрывает её интентом")
    func setupIsReadableAndFinishable() {
        let repository = InMemoryPreferenceRepository()
        let store = makeStore(repository: repository)
        #expect(store.setup.isFinished == false)

        store.finishSetup()

        #expect(store.setup.isFinished)
        #expect(repository.find(id: .default)?.setup.isFinished == true)
    }

    @Test("Единый тумблер уведомлений гасит всю группу и возвращает её целиком")
    func notificationsToggleFoldsWholeGroup() {
        let repository = InMemoryPreferenceRepository()
        let store = makeStore(repository: repository)
        #expect(store.notification.isMuted == false)

        store.toggleNotifications()

        #expect(store.notification.isMuted)
        #expect(repository.find(id: .default)?.notification.isMuted == true)
        // Один переход на нажатие, а не по записи на каждый вид уведомления.
        #expect(repository.saveCount == 1)

        store.toggleNotifications()

        #expect(store.notification.allows(type: .stageFinished))
        #expect(store.notification.allows(type: .reviewNeeded))
    }

    @Test("Выбранный агент уходит в хранилище")
    func chosenAgentIsPersisted() {
        let repository = InMemoryPreferenceRepository()
        let store = makeStore(repository: repository)
        #expect(store.agent.selected == nil)

        store.change(agent: .claudeCode)

        #expect(store.agent.selected == ToolId.claudeCode)
        #expect(repository.find(id: .default)?.agent.selected == ToolId.claudeCode)
    }

    @Test("Интент уходит в хранилище и обновляет чтение стора")
    func intentPersistsAndRefreshes() {
        let repository = InMemoryPreferenceRepository()
        let store = makeStore(repository: repository)

        store.toggleNotch()
        store.toggleMergeReview()

        #expect(!store.appearance.notchEnabled)
        #expect(!store.general.mergeReview)
        #expect(repository.find(id: .default)?.appearance.notchEnabled == false)
        #expect(repository.saveCount == 2)
    }
}
