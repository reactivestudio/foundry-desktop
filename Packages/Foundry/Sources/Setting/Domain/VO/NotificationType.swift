import Core

/**
 Вид уведомления — язык группы `Notification`. Это НЕ доменное событие (`DomainEvent`),
 а перечисление поводов, о которых можно уведомить; отдельный тип вместо строк/булей у
 вызывающего, чтобы `Notification` инкапсулировала множество включённых видов.
 Один тип — один файл.
 */
public enum NotificationType: ValueObject, CaseIterable {
    case stageFinished
    case stageFailed
    case reviewNeeded
}
