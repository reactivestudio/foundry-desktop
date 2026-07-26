import Domain
import Foundation

/// Адаптер порта `PreferenceStore` из Domain на системный `UserDefaults`.
/// Ключи (`openInClaudeDesktop`, `didFinishOnboarding`) — контракт хранения, не менять.
public struct UserDefaultsPreferenceStore: PreferenceStore {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func bool(forKey key: String) -> Bool? { defaults.object(forKey: key) as? Bool }

    public func setBool(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
}
