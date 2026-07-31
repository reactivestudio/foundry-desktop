import Core

/**
 Настройки связки с внешними инструментами — VO агрегата `Preference`. Сегодня флаг один:
 импортировать ли сессию рана во внешний просмотрщик агента (сейчас это Claude Code Desktop
 и deep link `claude://resume`, но КАКОЙ просмотрщик — деталь адаптера, а не настройки).

 Раньше этот флаг был полем сущности `Tool` со своим репозиторием поверх `UserDefaults`.
 Место было неверное: «импортировать сессию» — предпочтение пользователя, а не свойство
 инструмента (инструмент знает про установку, версию и путь). Потому флаг переехал сюда, а
 `Tool` освободил имя под будущий агрегат установленного инструментария.
 */
public struct Integration: ValueObject {
    /// Импортировать сессию рана во внешний просмотрщик агента. Дефолт — включено:
    /// смысл фичи в наблюдении рана из просмотрщика.
    public let opensSessionInViewer: Bool

    private init(opensSessionInViewer: Bool) {
        self.opensSessionInViewer = opensSessionInViewer
    }

    public static func of(opensSessionInViewer: Bool = true) -> Integration {
        Integration(opensSessionInViewer: opensSessionInViewer)
    }

    /// Переключить импорт сессии в просмотрщик — новый VO с инвертированным флагом.
    public func toggleOpensSessionInViewer() -> Integration {
        Integration(opensSessionInViewer: !opensSessionInViewer)
    }
}
