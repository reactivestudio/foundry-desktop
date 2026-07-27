import os

/// Системный лог CLI-слоя. Диагностика, которую нельзя терять в релизе (там, где
/// раньше стоял пустой `catch` или `try?`), уходит сюда — не в стирающий её в
/// продакшне `assertionFailure` и не в никуда.
enum CLILog {
    static let runner = Logger(subsystem: "Foundry", category: "ClaudeRunner")
    static let decoder = Logger(subsystem: "Foundry", category: "Decoder")
}
