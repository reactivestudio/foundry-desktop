import Testing

@testable import Setting

/// `PreferenceService` — граница согласованности настроек приложения (слой Application).
/// Проверяем три его обещания: дефолт вместо отсутствующего снимка, переход
/// read-modify-write целиком (соседние группы не теряются) и транзакционность —
/// падающий интент до хранилища не доходит.
@Suite("PreferenceService")
struct PreferenceServiceTests {

    @Test("current() отдаёт доменный дефолт, когда ничего не сохранено")
    func currentReturnsDomainDefault() {
        let service = PreferenceService(repository: InMemoryPreferenceRepository())

        let preference = service.current()

        #expect(preference.appearance.theme == .system)
        #expect(preference.appearance.notchEnabled)
        #expect(preference.general.mergeReview)
        #expect(!preference.general.launchAtLogin)
        #expect(preference.notification.allows(type: .stageFinished))
    }

    @Test("Интент сохраняет переход целиком, не задевая соседние группы")
    func intentPersistsWholeAggregate() {
        let repository = InMemoryPreferenceRepository()
        let service = PreferenceService(repository: repository)

        service.toggleNotch()

        #expect(!service.current().appearance.notchEnabled)
        #expect(service.current().general.mergeReview)
        #expect(repository.saveCount == 1)
    }

    @Test("Интенты накапливаются: каждый читает актуальный набор, а не дефолт")
    func intentsAccumulate() {
        let service = PreferenceService(repository: InMemoryPreferenceRepository())

        service.change(theme: .dark)
        service.toggleLaunchAtLogin()
        service.disableNotification(for: .reviewNeeded)

        let preference = service.current()
        #expect(preference.appearance.theme == .dark)
        #expect(preference.general.launchAtLogin)
        #expect(!preference.notification.allows(type: .reviewNeeded))
        #expect(preference.notification.allows(type: .stageFinished))
    }

    @Test("Падающий интент не доходит до сохранения — полусостояния в хранилище нет")
    func failingIntentSavesNothing() throws {
        let repository = InMemoryPreferenceRepository()
        let service = PreferenceService(repository: repository)
        try service.rename(firstName: "Ada", lastName: "Lovelace")

        let tooLongName = String(repeating: "a", count: Profile.maxNameLength + 1)
        #expect(throws: NameTooLongError.self) {
            try service.rename(firstName: tooLongName, lastName: "Lovelace")
        }

        #expect(repository.saveCount == 1)
        #expect(service.current().profile.firstName == "Ada")
    }
}
