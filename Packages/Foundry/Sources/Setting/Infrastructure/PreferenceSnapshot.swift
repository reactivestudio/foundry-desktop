import Foundation

/**
 Персистентный снимок агрегата `Preference` — плоское `Codable`-представление для
 хранилища (plist). Живёт в Infrastructure намеренно: домен (агрегат и VO) НЕ `Codable`,
 чтобы формат хранения не пробивал доменный слой. Снимок — единственное место, знающее,
 как настройки ложатся на диск: имена полей = ключи plist (контракт хранения), а доменные
 перечни `Theme`/`NotificationType` кодируются именами кейсов (маппинг строк — здесь, не
 в домене).

 ВСЕ поля опциональны, и это не небрежность, а правило эволюции: снимок на диске всегда
 старше кода. Отсутствующий ключ значит «настройка не задавалась» → берём ДОМЕННЫЙ дефолт
 из фабрики группы (чтобы дефолт не раздваивался между слоями), а не роняем весь набор.
 Иначе первое же новое поле объявляло бы все сохранённые настройки битыми и молча сбрасывало
 их целиком — ровно это случилось бы сейчас, когда к снимку прибавились `opensSessionInViewer`
 и `setupFinished`.

 Обратный маппинг `toPreference(id:)` собирает агрегат через доменные фабрики, поэтому
 битые данные с диска (слишком длинное имя, неизвестная тема) не рождают невалидный
 агрегат, а бросают ошибку — репозиторий трактует её как «валидного снимка нет».
 */
public struct PreferenceSnapshot: Codable {
    // Профиль.
    var firstName: String?
    var lastName: String?
    var avatarReference: String?
    // Оформление.
    var theme: String?
    var notchEnabled: Bool?
    // Общие.
    var launchAtLogin: Bool?
    var tokensInKeychain: Bool?
    var mergeReview: Bool?
    // Доступность.
    var reduceMotion: Bool?
    var largerText: Bool?
    var higherContrast: Bool?
    // Уведомления — имена включённых видов. Пустой массив (все виды выключены) и отсутствие
    // ключа (не задавалось) — РАЗНЫЕ вещи, потому именно опциональный массив.
    var enabledNotificationTypes: [String]?
    // Связка с внешними инструментами.
    var opensSessionInViewer: Bool?
    // Выбранный агент — id инструмента (значения id и есть контракт хранения).
    var selectedAgent: String?
    // Первичная настройка.
    var setupFinished: Bool?

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
        opensSessionInViewer = preference.integration.opensSessionInViewer
        selectedAgent = preference.agent.selected?.value
        setupFinished = preference.setup.isFinished
    }

    /**
     Собрать агрегат из снимка (маппинг хранилище → домен) через доменные фабрики.
     Бросает, если снимок не бьётся с инвариантами домена (например, имя длиннее предела)
     или содержит неизвестное имя перечня, — тогда это не валидный набор настроек.
     */
    public func toPreference(id: PreferenceId) throws -> Preference {
        Preference.of(
            id: id,
            profile: try profile(),
            appearance: try appearance(),
            notification: try notification(),
            general: general(),
            accessibility: accessibility(),
            integration: integration(),
            agent: try agent(),
            setup: setup()
        )
    }

    // MARK: - Сборка групп (недостающее поле = доменный дефолт группы)

    private func profile() throws -> Profile {
        let defaults = Profile.empty
        let avatar = try avatarReference.map { reference in try Avatar.of(reference: reference) }

        return try Profile.of(
            firstName: firstName ?? defaults.firstName,
            lastName: lastName ?? defaults.lastName,
            avatar: avatar
        )
    }

    private func appearance() throws -> Appearance {
        let defaults = Appearance.of()
        let storedTheme = try theme.map { name in try Self.theme(named: name) }

        return Appearance.of(
            theme: storedTheme ?? defaults.theme,
            notchEnabled: notchEnabled ?? defaults.notchEnabled
        )
    }

    private func notification() throws -> Notification {
        guard let names = enabledNotificationTypes else {
            return Notification.of()
        }
        let types = try names.map { name in try Self.notificationType(named: name) }

        return Notification.of(enabledTypes: Set(types))
    }

    private func general() -> General {
        let defaults = General.of()

        return General.of(
            launchAtLogin: launchAtLogin ?? defaults.launchAtLogin,
            tokensInKeychain: tokensInKeychain ?? defaults.tokensInKeychain,
            mergeReview: mergeReview ?? defaults.mergeReview
        )
    }

    private func accessibility() -> Accessibility {
        let defaults = Accessibility.of()

        return Accessibility.of(
            reduceMotion: reduceMotion ?? defaults.reduceMotion,
            largerText: largerText ?? defaults.largerText,
            higherContrast: higherContrast ?? defaults.higherContrast
        )
    }

    private func integration() -> Integration {
        let defaults = Integration.of()

        return Integration.of(opensSessionInViewer: opensSessionInViewer ?? defaults.opensSessionInViewer)
    }

    /// Неизвестный id агента — не повод считать набор битым: инструмент могли
    /// переименовать или выкинуть, а выбор — это всего лишь одна настройка. Пустое
    /// значение фабрика id отвергнет, и вот это уже битый снимок.
    private func agent() throws -> Agent {
        guard let selectedAgent else {
            return Agent.of()
        }

        return Agent.of(selected: try ToolId.of(value: selectedAgent))
    }

    private func setup() -> Setup {
        let defaults = Setup.of()

        return Setup.of(isFinished: setupFinished ?? defaults.isFinished)
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
