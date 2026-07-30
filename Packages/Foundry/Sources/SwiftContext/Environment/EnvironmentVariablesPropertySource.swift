import Foundation

/// Источник свойств из переменных окружения процесса. Как в Spring — relaxed binding: ключ
/// `foundry.storage.dir` ищется и как есть, и в UPPER_SNAKE (`FOUNDRY_STORAGE_DIR`), потому
/// что env-переменные традиционно в верхнем регистре с подчёркиваниями.
public struct EnvironmentVariablesPropertySource: PropertySource {
    private let values: [String: String]

    public init(values: [String: String] = ProcessInfo.processInfo.environment) {
        self.values = values
    }

    public func getProperty(name: String) -> String? {
        if let direct = values[name] {
            return direct
        }
        let relaxed = name.uppercased().replacingOccurrences(of: ".", with: "_")

        return values[relaxed]
    }
}
