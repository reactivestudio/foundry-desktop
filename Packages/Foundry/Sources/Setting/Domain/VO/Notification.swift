import Core

/**
 О каких видах событий рана уведомлять — VO агрегата `Preference`. Хранит МНОЖЕСТВО
 включённых видов (`enabledTypes`): наличие вида = уведомляем, отсутствие = молчим.
 Так `enable`/`disable`/`allows` — это insert/remove/contains без ветвлений. Наружу
 отдаёт свой язык: `allows(type:)`, `isMuted`. Это НАШИ настройки; не путать с
 разрешением ОС на показ уведомлений — оно принадлежит системе, живёт за Gateway и не
 хранится. Имя совпадает с `Foundation.Notification` — где нужен Foundation, разводят
 как `Setting.Notification` (агрегат зовётся `Preference`, имя модуля не затенено).
 */
public struct Notification: ValueObject {
    /// Включённые виды уведомлений; отсутствие вида в множестве = он выключен.
    public let enabledTypes: Set<NotificationType>

    private init(enabledTypes: Set<NotificationType>) {
        self.enabledTypes = enabledTypes
    }

    /// По умолчанию включены все виды.
    public static func of(
        enabledTypes: Set<NotificationType> = Set(NotificationType.allCases)
    ) -> Notification {
        Notification(enabledTypes: enabledTypes)
    }

    /// Включить вид уведомления — новый VO с добавленным видом.
    public func enable(for type: NotificationType) -> Notification {
        Notification(enabledTypes: enabledTypes.union([type]))
    }

    /// Выключить вид уведомления — новый VO без этого вида.
    public func disable(for type: NotificationType) -> Notification {
        Notification(enabledTypes: enabledTypes.subtracting([type]))
    }

    /// Молчать обо всём — новый VO с пустым множеством. Молчание это ОТСУТСТВИЕ
    /// включённых видов, а не отдельный флаг «выключено»: иначе у настройки было бы
    /// два источника истины и состояние «флаг выключен, но вид включён».
    public func mute() -> Notification {
        Notification(enabledTypes: [])
    }

    /// Вернуть звук — включаются ВСЕ виды. Какие были включены до `mute`, VO не
    /// помнит намеренно: помнить их значило бы держать теневое состояние рядом с
    /// настоящим. Нужен точный набор — его задают `enable(for:)`/`disable(for:)`.
    public func unmute() -> Notification {
        Notification(enabledTypes: Set(NotificationType.allCases))
    }

    /// Уведомлять ли об этом виде.
    public func allows(type: NotificationType) -> Bool {
        enabledTypes.contains(type)
    }

    /// Все уведомления выключены — можно не тревожить систему вовсе.
    public var isMuted: Bool {
        enabledTypes.isEmpty
    }
}
