import Foundation

/// Адаптер порта `ToolRepository` из Domain на системный `UserDefaults`.
/// Ключ `openInClaudeDesktop` — контракт хранения (persisted-значение, миграции
/// нет), не менять. Отсутствие ключа = настройка не задавалась → домен применяет
/// свой дефолт (см. `Tool`), поэтому `load` переопределяет поле только когда
/// значение реально сохранено.
public struct UserDefaultsToolRepository: ToolRepository {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    private static let opensSessionInViewerKey = "openInClaudeDesktop"

    public func load() -> Tool {
        var tool = Tool()
        if let stored = defaults.object(forKey: Self.opensSessionInViewerKey) as? Bool {
            tool.opensSessionInViewer = stored
        }
        return tool
    }

    public func save(_ tool: Tool) {
        defaults.set(tool.opensSessionInViewer, forKey: Self.opensSessionInViewerKey)
    }
}
