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
