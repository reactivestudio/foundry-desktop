import SwiftContext

/// Сценарий работы с настройками инструментов (use-case, слой Application) —
/// граница согласованности их изменений. Presentation не грузит-меняет-сохраняет
/// сам: он выражает интент («импортировать сессию в просмотрщик — вкл/выкл»), а
/// служба выполняет переход атомарно поверх порта репозитория (читает актуальную
/// сущность, применяет изменение, сохраняет целиком). Бизнес-правил домена здесь
/// нет — только оркестрация; дефолты живут в самом `Tool`.
///
/// Не `@MainActor`: у службы нет состояния, привязанного к главному актору, — она
/// лишь ходит в порт хранилища, потокобезопасный сам по себе. Регистрируется сканом
/// как `@Component` (порта у службы нет — её резолвят по конкретному типу); в отличие
/// от `RunService`, который `@MainActor` и собирается в bootstrap конструктором.
@Component
public final class ToolService {
    private let repository: ToolRepository

    public init(repository: ToolRepository) {
        self.repository = repository
    }

    /// Снимок текущих настроек инструментов — для первичной раздачи в состояние экрана.
    public func current() -> Tool {
        repository.load()
    }

    /// Импортировать сессию рана во внешний просмотрщик — вкл/выкл. Переход атомарен:
    /// читает актуальную сущность, применяет флаг, сохраняет её целиком.
    public func setOpensSessionInViewer(enabled: Bool) {
        var tool = repository.load()
        tool.opensSessionInViewer = enabled
        repository.save(tool: tool)
    }
}
