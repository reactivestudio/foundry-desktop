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
 без единого заданного поля). `Tool` вольётся сюда полем при миграции существующего
 агрегата `Tool`. `Permission` в агрегат НЕ входит — это статусы ОС за Gateway.
 */
public final class Preference: AggregateRoot<PreferenceId> {
    public private(set) var profile: Profile
    public private(set) var appearance: Appearance
    public private(set) var notification: Notification
    public private(set) var general: General
    public private(set) var accessibility: Accessibility

    private init(
        id: PreferenceId,
        profile: Profile,
        appearance: Appearance,
        notification: Notification,
        general: General,
        accessibility: Accessibility
    ) {
        self.profile = profile
        self.appearance = appearance
        self.notification = notification
        self.general = general
        self.accessibility = accessibility
        super.init(id: id)
    }

    public static func of(
        id: PreferenceId = .default,
        profile: Profile = .empty,
        appearance: Appearance = .of(),
        notification: Notification = .of(),
        general: General = .of(),
        accessibility: Accessibility = .of()
    ) -> Preference {
        Preference(
            id: id,
            profile: profile,
            appearance: appearance,
            notification: notification,
            general: general,
            accessibility: accessibility
        )
    }

    // MARK: - Appearance

    public func change(theme: Theme) {
        mutate {
            appearance = appearance.change(theme: theme)
        }
    }

    public func toggleNotch() {
        mutate {
            appearance = appearance.toggleNotch()
        }
    }

    // MARK: - General

    public func toggleLaunchAtLogin() {
        mutate {
            general = general.toggleLaunchAtLogin()
        }
    }

    public func toggleTokensInKeychain() {
        mutate {
            general = general.toggleTokensInKeychain()
        }
    }

    public func toggleMergeReview() {
        mutate {
            general = general.toggleMergeReview()
        }
    }

    // MARK: - Accessibility

    public func toggleReduceMotion() {
        mutate {
            accessibility = accessibility.toggleReduceMotion()
        }
    }

    public func toggleLargerText() {
        mutate {
            accessibility = accessibility.toggleLargerText()
        }
    }

    public func toggleHigherContrast() {
        mutate {
            accessibility = accessibility.toggleHigherContrast()
        }
    }

    // MARK: - Notification

    public func enableNotification(for type: NotificationType) {
        mutate {
            notification = notification.enable(for: type)
        }
    }

    public func disableNotification(for type: NotificationType) {
        mutate {
            notification = notification.disable(for: type)
        }
    }

    // MARK: - Profile

    public func rename(firstName: String, lastName: String) throws {
        let renamed = try profile.rename(firstName: firstName, lastName: lastName)
        mutate {
            profile = renamed
        }
    }

    public func change(avatar: Avatar?) {
        mutate {
            profile = profile.change(avatar: avatar)
        }
    }

    // MARK: - Инварианты

    /**
     Кросс-групповые инварианты агрегата; зовётся автоматически из `mutate` после каждого
     изменения (в Swift нет AOP, но `mutate` — единая точка, где проверку не забыть).
     Здесь только инварианты класса «этого не может быть = баг кода» → `precondition`
     (аналог Kotlin `check()`); восстановимую валидацию входа делают фабрики VO через
     `require` (аналог Kotlin `require()`). Пример правила, когда появится:
     `precondition(!general.launchAtLogin || general.tokensInKeychain)`. Пока
     кросс-групповых правил нет — это защищённая точка, куда они лягут, а не «проверим
     где-нибудь потом».
     */
    override public func checkInvariants() {}
}
