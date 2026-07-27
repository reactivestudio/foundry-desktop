import os

/// Системный лог UI-слоя. `assertionFailure` в релизе — no-op: сбой сборки
/// рендерера там проходил бесследно, оставляя пустой орб без единой записи.
/// Теперь такие сбои пишутся сюда на уровне `.fault`.
public enum FeatureLog {
    public static let swarm = Logger(subsystem: "Foundry", category: "Swarm")
    public static let domain = Logger(subsystem: "Foundry", category: "Domain")
}
