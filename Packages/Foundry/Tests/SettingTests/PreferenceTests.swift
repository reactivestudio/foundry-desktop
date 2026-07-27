@testable import Setting
import Testing

@Suite("Агрегат Preference")
struct PreferenceTests {

    @Test("Фабрика даёт валидный агрегат с доменными дефолтами")
    func factoryDefaults() {
        let preference = Preference.of()
        #expect(preference.id == PreferenceId.default)
        #expect(preference.profile.fullName == "")
        #expect(preference.appearance.theme == .system)
        #expect(preference.general.tokensInKeychain)
        #expect(preference.accessibility.reduceMotion == false)
    }

    @Test("Команды оформления меняют свою группу")
    func appearanceCommands() {
        let preference = Preference.of()
        preference.change(theme: .dark)
        #expect(preference.appearance.theme == .dark)

        let before = preference.appearance.notchEnabled
        preference.toggleNotch()
        #expect(preference.appearance.notchEnabled == !before)
    }

    @Test("Команды общих настроек переключают флаги")
    func generalCommands() {
        let preference = Preference.of()
        let before = preference.general.launchAtLogin
        preference.toggleLaunchAtLogin()
        #expect(preference.general.launchAtLogin == !before)
    }

    @Test("Команды уведомлений включают и выключают вид")
    func notificationCommands() {
        let preference = Preference.of()
        preference.disableNotification(for: .reviewNeeded)
        #expect(preference.notification.allows(type: .reviewNeeded) == false)

        preference.enableNotification(for: .reviewNeeded)
        #expect(preference.notification.allows(type: .reviewNeeded))
    }

    @Test("Переименование меняет профиль, слишком длинное имя — ошибка")
    func renameCommand() throws {
        let preference = Preference.of()
        try preference.rename(firstName: "Ada", lastName: "Lovelace")
        #expect(preference.profile.fullName == "Ada Lovelace")

        let overLimit = String(repeating: "a", count: Profile.maxNameLength + 1)
        #expect(throws: NameTooLongError.self) {
            try preference.rename(firstName: overLimit, lastName: "")
        }
        // Проваленная команда не тронула состояние.
        #expect(preference.profile.fullName == "Ada Lovelace")
    }

    @Test("Смена аватара отражается в профиле")
    func avatarCommand() throws {
        let preference = Preference.of()
        let avatar = try Avatar.of(reference: "me.png")
        preference.change(avatar: avatar)
        #expect(preference.profile.avatar == avatar)
    }

    @Test("Равенство агрегата — по идентичности, не по полям")
    func equalityById() throws {
        let same = try PreferenceId.of(value: "team")
        let one = Preference.of(id: same)
        let two = Preference.of(id: same)
        one.change(theme: .dark) // поля разошлись, id тот же
        #expect(one == two)

        let other = Preference.of(id: PreferenceId.default)
        #expect(one != other)
    }
}
