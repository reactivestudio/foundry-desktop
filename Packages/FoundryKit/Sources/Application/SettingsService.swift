import Domain

/// Сценарий работы с пользовательскими настройками (use-case, слой Application) —
/// граница согласованности их изменений. Presentation не грузит-меняет-сохраняет
/// сам: он выражает интент («импортировать сессию в просмотрщик — вкл/выкл»), а
/// служба выполняет переход атомарно поверх порта репозитория (читает актуальный
/// агрегат, применяет изменение, сохраняет целиком). Бизнес-правил домена здесь
/// нет — только оркестрация; дефолты живут в самом `Settings`.
///
/// Не `@MainActor`: у службы нет состояния, привязанного к главному актору, — она
/// лишь ходит в порт хранилища, потокобезопасный сам по себе. Поэтому регистрируется
/// обычным Swinject-бином (в отличие от `RunService`, который `@MainActor`).
public final class SettingsService {
    private let repository: SettingsRepository

    public init(repository: SettingsRepository) {
        self.repository = repository
    }

    /// Снимок текущих настроек — для первичной раздачи в состояние экрана.
    public func current() -> Settings {
        repository.load()
    }

    /// Импортировать сессию рана во внешний просмотрщик — вкл/выкл. Переход атомарен:
    /// читает актуальные настройки, применяет флаг, сохраняет агрегат целиком.
    public func setOpensSessionInViewer(_ enabled: Bool) {
        var settings = repository.load()
        settings.opensSessionInViewer = enabled
        repository.save(settings)
    }
}
