import Core

/**
 Тема оформления — VO группы `Appearance`. Чистый доменный перечень БЕЗ сырых строк:
 домен не знает, как тема сериализуется или как ложится на системную тему macOS.
 Персистентное представление (Codable-DTO, raw = имена кейсов) живёт в Infrastructure,
 маппинг на `NSAppearance`/`ColorScheme` — в Presentation. Так строки-константы не
 пробивают слой домена.
 */
public enum Theme: ValueObject, CaseIterable {
    case system
    case light
    case dark
}
