import Core
@testable import Setting
import Testing

@Suite("Value-объекты настроек")
struct ValueObjectTests {

    // ── Avatar ────────────────────────────────────────────────────────────────

    @Test("Пустая ссылка на аватар — доменная ошибка")
    func blankAvatarRejected() {
        #expect(throws: EmptyAvatarReferenceError.self) {
            try Avatar.of(reference: "   ")
        }
    }

    @Test("Непустая ссылка сохраняется как есть")
    func avatarKeepsReference() throws {
        #expect(try Avatar.of(reference: "photo.png").reference == "photo.png")
    }

    // ── PreferenceId ──────────────────────────────────────────────────────────

    @Test("Пустой id — доменная ошибка")
    func blankPreferenceIdRejected() {
        #expect(throws: EmptyIdentityValueError.self) {
            try PreferenceId.of(value: " \n ")
        }
    }

    @Test("Фабрика id нормализует пробелы")
    func preferenceIdTrims() throws {
        #expect(try PreferenceId.of(value: "  team  ").value == "team")
    }

    @Test("Дефолтный id имеет значение default")
    func defaultPreferenceIdValue() {
        #expect(PreferenceId.default.value == "default")
    }

    @Test("Равенство id по значению")
    func preferenceIdEqualsByValue() throws {
        #expect(try PreferenceId.of(value: "team") == PreferenceId.of(value: "team"))
        #expect(try PreferenceId.of(value: "team") != PreferenceId.of(value: "other"))
    }

    // ── Appearance ────────────────────────────────────────────────────────────

    @Test("Оформление: дефолты и намеренные изменения")
    func appearanceDefaultsAndChanges() {
        let appearance = Appearance.of()
        #expect(appearance.theme == .system)
        #expect(appearance.notchEnabled)

        #expect(appearance.change(theme: .dark).theme == .dark)
        #expect(appearance.toggleNotch().notchEnabled == false)
        // Смена темы не трогает чёлку, и наоборот.
        #expect(appearance.change(theme: .dark).notchEnabled == appearance.notchEnabled)
        #expect(appearance.toggleNotch().theme == appearance.theme)
    }

    // ── General ───────────────────────────────────────────────────────────────

    @Test("Общие: тумблеры переключают только своё поле")
    func generalTogglesAreIsolated() {
        let general = General.of()
        #expect(general.launchAtLogin == false)
        #expect(general.tokensInKeychain)
        #expect(general.mergeReview)

        let flipped = general.toggleLaunchAtLogin()
        #expect(flipped.launchAtLogin)
        #expect(flipped.tokensInKeychain == general.tokensInKeychain)
        #expect(flipped.mergeReview == general.mergeReview)
    }

    // ── Accessibility ─────────────────────────────────────────────────────────

    @Test("Доступность: тумблеры переключают только своё поле")
    func accessibilityTogglesAreIsolated() {
        let access = Accessibility.of()
        #expect(access.reduceMotion == false)

        let flipped = access.toggleLargerText()
        #expect(flipped.largerText)
        #expect(flipped.reduceMotion == access.reduceMotion)
        #expect(flipped.higherContrast == access.higherContrast)
    }

    // ── Notification ──────────────────────────────────────────────────────────

    @Test("Уведомления: по умолчанию включены все виды")
    func notificationDefaultsAllEnabled() {
        let notification = Setting.Notification.of()
        for type in NotificationType.allCases {
            #expect(notification.allows(type: type))
        }
        #expect(notification.isMuted == false)
    }

    @Test("Уведомления: disable/enable отражаются в allows и isMuted")
    func notificationEnableDisable() {
        var notification = Setting.Notification.of()
        for type in NotificationType.allCases {
            notification = notification.disable(for: type)
        }
        #expect(notification.isMuted)
        #expect(notification.allows(type: .stageFinished) == false)

        notification = notification.enable(for: .stageFinished)
        #expect(notification.allows(type: .stageFinished))
        #expect(notification.isMuted == false)
    }
}
