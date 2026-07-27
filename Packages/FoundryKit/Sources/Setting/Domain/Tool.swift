/// Сущность настроек инструментов — агента и foundry cli (в терминах BC `Setting`
/// это одна из сущностей наравне с Profile, Notification, Appearance, Access,
/// General). Сегодня durable-настройка ровно одна — импортировать ли сессию рана
/// во внешний просмотрщик агента; тип структурирован под рост: новые настройки
/// инструментов станут полями рядом, каждая со своим дефолтом. Значения задаются с
/// дефолтами при создании, поэтому объект всегда в валидном состоянии, а дефолт
/// живёт в одном месте — здесь, в домене (адаптер хранилища лишь переопределяет
/// поле, если ключ уже сохранён).
public struct Tool: Sendable, Equatable {
    /// Импортировать сессию рана во внешний просмотрщик агента (сегодня — Claude
    /// Code Desktop, deep link claude://resume). Дефолт — включено: смысл фичи в
    /// наблюдении рана из просмотрщика.
    public var opensSessionInViewer: Bool

    public init(opensSessionInViewer: Bool = true) {
        self.opensSessionInViewer = opensSessionInViewer
    }
}
