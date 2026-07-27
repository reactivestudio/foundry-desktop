import Domain
import Foundation

/// Адаптер порта `SettingsRepository` из Domain на системный `UserDefaults`.
/// Ключ `openInClaudeDesktop` — контракт хранения (persisted-значение, миграции
/// нет), не менять. Отсутствие ключа = настройка не задавалась → домен применяет
/// свой дефолт (см. `Settings`), поэтому `load` переопределяет поле только когда
/// значение реально сохранено.
public struct UserDefaultsSettingsRepository: SettingsRepository {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    private static let opensSessionInViewerKey = "openInClaudeDesktop"

    public func load() -> Settings {
        var settings = Settings()
        if let stored = defaults.object(forKey: Self.opensSessionInViewerKey) as? Bool {
            settings.opensSessionInViewer = stored
        }
        return settings
    }

    public func save(_ settings: Settings) {
        defaults.set(settings.opensSessionInViewer, forKey: Self.opensSessionInViewerKey)
    }
}
