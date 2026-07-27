import Core

/**
 Настройки оформления — VO агрегата `Preference`: тема и режим чёлки. Иммутабелен;
 создаётся фабрикой `of` (дефолты живут здесь). Меняют его намеренными методами:
 значение — `change(theme:)`, булев флаг — `toggleNotch()` (флип); оба возвращают новый
 VO, поля неизменны.
 */
public struct Appearance: ValueObject {
    public let theme: Theme
    public let notchEnabled: Bool

    private init(theme: Theme, notchEnabled: Bool) {
        self.theme = theme
        self.notchEnabled = notchEnabled
    }

    public static func of(theme: Theme = .system, notchEnabled: Bool = true) -> Appearance {
        Appearance(theme: theme, notchEnabled: notchEnabled)
    }

    /// Сменить тему — новый VO с заданной темой.
    public func change(theme: Theme) -> Appearance {
        with(theme: theme)
    }

    /// Переключить режим чёлки — новый VO с инвертированным флагом.
    public func toggleNotch() -> Appearance {
        with(notchEnabled: !notchEnabled)
    }

    /**
     Копия с точечной заменой полей (`nil` — оставить как есть). Приватная: повтор
     перечисления всех полей живёт в одном месте, наружу — только намерения
     `change`/`toggleNotch`.
     */
    private func with(theme: Theme? = nil, notchEnabled: Bool? = nil) -> Appearance {
        Appearance(theme: theme ?? self.theme, notchEnabled: notchEnabled ?? self.notchEnabled)
    }
}
