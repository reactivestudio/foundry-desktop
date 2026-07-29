import Foundation

/**
 Персистентный снимок агрегата `Preference` — плоское `Codable`-представление для
 хранилища (plist). Живёт в Infrastructure намеренно: домен (агрегат и VO) НЕ `Codable`,
 чтобы формат хранения не пробивал доменный слой. Снимок — единственное место, знающее,
 как настройки ложатся на диск: имена полей = ключи plist (контракт хранения), а доменные
 перечни `Theme`/`NotificationType` кодируются именами кейсов (маппинг строк — здесь, не
 в домене).

 Обратный маппинг `toPreference(id:)` собирает агрегат через доменные фабрики, поэтому
 битые данные с диска (слишком длинное имя, неизвестная тема) не рождают невалидный
 агрегат, а бросают ошибку — репозиторий трактует её как «валидного снимка нет».
 */
public struct PreferenceSnapshot: Codable {
    // Профиль.
    var firstName: String
    var lastName: String
    var avatarReference: String?
    // Оформление.
    var theme: String
    var notchEnabled: Bool
    // Общие.
    var launchAtLogin: Bool
    var tokensInKeychain: Bool
    var mergeReview: Bool
    // Доступность.
    var reduceMotion: Bool
    var largerText: Bool
    var higherContrast: Bool
    // Уведомления — имена включённых видов.
    var enabledNotificationTypes: [String]

    /// Снять снимок с агрегата для сохранения (маппинг домен → хранилище).
    public init(from preference: Preference) {
        firstName = preference.profile.firstName
        lastName = preference.profile.lastName
        avatarReference = preference.profile.avatar?.reference
        theme = Self.name(of: preference.appearance.theme)
        notchEnabled = preference.appearance.notchEnabled
        launchAtLogin = preference.general.launchAtLogin
        tokensInKeychain = preference.general.tokensInKeychain
        mergeReview = preference.general.mergeReview
        reduceMotion = preference.accessibility.reduceMotion
        largerText = preference.accessibility.largerText
        higherContrast = preference.accessibility.higherContrast
        enabledNotificationTypes = preference.notification.enabledTypes.map(Self.name(of:))
    }

    /**
     Собрать агрегат из снимка (маппинг хранилище → домен) через доменные фабрики.
     Бросает, если снимок не бьётся с инвариантами домена (например, имя длиннее предела)
     или содержит неизвестное имя перечня, — тогда это не валидный набор настроек.
     */
    public func toPreference(id: PreferenceId) throws -> Preference {
        let avatar = try avatarReference.map { reference in try Avatar.of(reference: reference) }
        let profile = try Profile.of(firstName: firstName, lastName: lastName, avatar: avatar)
        let appearance = try Appearance.of(theme: Self.theme(named: theme), notchEnabled: notchEnabled)
        let general = General.of(
            launchAtLogin: launchAtLogin,
            tokensInKeychain: tokensInKeychain,
            mergeReview: mergeReview
        )
        let accessibility = Accessibility.of(
            reduceMotion: reduceMotion,
            largerText: largerText,
            higherContrast: higherContrast
        )
        let types = try enabledNotificationTypes.map { name in try Self.notificationType(named: name) }
        let notification = Notification.of(enabledTypes: Set(types))

        return Preference.of(
            id: id,
            profile: profile,
            appearance: appearance,
            notification: notification,
            general: general,
            accessibility: accessibility
        )
    }

    // MARK: - Маппинг перечней (имена кейсов — контракт хранения)

    private static func name(of theme: Theme) -> String {
        switch theme {
        case .system: "system"
        case .light: "light"
        case .dark: "dark"
        }
    }

    private static func theme(named name: String) throws -> Theme {
        switch name {
        case "system": .system
        case "light": .light
        case "dark": .dark
        default: throw UnknownPersistedValueError(field: "theme", value: name)
        }
    }

    private static func name(of type: NotificationType) -> String {
        switch type {
        case .stageFinished: "stageFinished"
        case .stageFailed: "stageFailed"
        case .reviewNeeded: "reviewNeeded"
        }
    }

    private static func notificationType(named name: String) throws -> NotificationType {
        switch name {
        case "stageFinished": .stageFinished
        case "stageFailed": .stageFailed
        case "reviewNeeded": .reviewNeeded
        default: throw UnknownPersistedValueError(field: "notificationType", value: name)
        }
    }
}
