import Core

/**
 Агрегат настроек приложения — единственный корень BC `Setting`. Мутабельный
 `AggregateRoot` (ссылочный: одна и та же вещь, меняющаяся во времени), в корне
 Domain. Собирает группы-VO и является ЕДИНСТВЕННОЙ точкой их изменения: снаружи
 в под-VO не лезут (поля `private(set)`), а зовут намерение у корня: значения —
 `change(...)`/`rename`, булевы флаги — `toggle…()`, уведомления —
 `enable/disableNotification(for:)`. Команды мутируют состояние и НИЧЕГО не возвращают
 (tell-don't-ask); после каждого изменения корень проверяет свои инварианты.

 Создаётся фабрикой `of` (каждая группа с доменным дефолтом, поэтому агрегат валиден
 без единого заданного поля). `Permission` в агрегат НЕ входит — это статусы ОС за Gateway.

 `@Invariants` на классе — проверка инвариантов на весь корень: аннотация дописывает вызов
 `checkInvariants` в каждую команду и инициализатор, поэтому команды пишутся плоско, без
 обёртки вокруг изменения, а на новой команде проверку не забыть. Отдельной команде можно
 назначить свою проверку — `@Invariant(check:)` прямо на ней, она старше классовой.
 */
@Invariants
public final class Preference: AggregateRoot<PreferenceId> {
    public private(set) var profile: Profile
    public private(set) var appearance: Appearance
    public private(set) var notification: Notification
    public private(set) var general: General
    public private(set) var accessibility: Accessibility
    public private(set) var integration: Integration
    public private(set) var agent: Agent
    public private(set) var setup: Setup

    private init(
        id: PreferenceId,
        profile: Profile,
        appearance: Appearance,
        notification: Notification,
        general: General,
        accessibility: Accessibility,
        integration: Integration,
        agent: Agent,
        setup: Setup
    ) {
        self.profile = profile
        self.appearance = appearance
        self.notification = notification
        self.general = general
        self.accessibility = accessibility
        self.integration = integration
        self.agent = agent
        self.setup = setup
        super.init(id: id)
    }

    public static func of(
        id: PreferenceId = .default,
        profile: Profile = .empty,
        appearance: Appearance = .of(),
        notification: Notification = .of(),
        general: General = .of(),
        accessibility: Accessibility = .of(),
        integration: Integration = .of(),
        agent: Agent = .of(),
        setup: Setup = .of()
    ) -> Preference {
        Preference(
            id: id,
            profile: profile,
            appearance: appearance,
            notification: notification,
            general: general,
            accessibility: accessibility,
            integration: integration,
            agent: agent,
            setup: setup
        )
    }

    // MARK: - Appearance

    public func change(theme: Theme) {
        appearance = appearance.change(theme: theme)
    }

    public func toggleNotch() {
        appearance = appearance.toggleNotch()
    }

    // MARK: - General

    public func toggleLaunchAtLogin() {
        general = general.toggleLaunchAtLogin()
    }

    public func toggleTokensInKeychain() {
        general = general.toggleTokensInKeychain()
    }

    public func toggleMergeReview() {
        general = general.toggleMergeReview()
    }

    // MARK: - Accessibility

    public func toggleReduceMotion() {
        accessibility = accessibility.toggleReduceMotion()
    }

    public func toggleLargerText() {
        accessibility = accessibility.toggleLargerText()
    }

    public func toggleHigherContrast() {
        accessibility = accessibility.toggleHigherContrast()
    }

    // MARK: - Notification

    public func enableNotification(for type: NotificationType) {
        notification = notification.enable(for: type)
    }

    public func disableNotification(for type: NotificationType) {
        notification = notification.disable(for: type)
    }

    /// Молчать обо всём. Идемпотентно; не `toggle…`, потому что противоположность
    /// молчания — не «один флаг наоборот», а включённый набор видов.
    public func muteNotifications() {
        notification = notification.mute()
    }

    /// Уведомлять обо всех видах. Идемпотентно.
    public func unmuteNotifications() {
        notification = notification.unmute()
    }

    // MARK: - Integration

    public func toggleOpensSessionInViewer() {
        integration = integration.toggleOpensSessionInViewer()
    }

    // MARK: - Agent

    /// Выбрать агента, который гоняет стадии. Настройка, а не факт о системе: выбор
    /// переживает удаление CLI (установленность живёт в агрегате `Tool`).
    public func change(agent: ToolId) {
        self.agent = self.agent.change(selected: agent)
    }

    // MARK: - Setup

    /// Отметить мастер первого запуска пройденным. Идемпотентно.
    public func finishSetup() {
        setup = setup.finish()
    }

    // MARK: - Profile

    public func rename(firstName: String, lastName: String) throws {
        profile = try profile.rename(firstName: firstName, lastName: lastName)
    }

    public func change(avatar: Avatar?) {
        profile = profile.change(avatar: avatar)
    }

    // MARK: - Инварианты

    /**
     Кросс-групповые инварианты агрегата; зовётся на выходе из каждой команды и
     инициализатора — вызовы расставляет классовая аннотация `@Invariants`.
     Здесь только инварианты класса «этого не может быть = баг кода» → `check(correct:)`
     (аналог Kotlin `check()`); восстановимую валидацию входа делают фабрики VO через
     `require` (аналог Kotlin `require()`). Пример правила, когда появится:
     `check(correct: !general.launchAtLogin || general.tokensInKeychain)`. Пока
     кросс-групповых правил нет — это защищённая точка, куда они лягут, а не «проверим
     где-нибудь потом».
     */
    override public func checkInvariants() {}
}
