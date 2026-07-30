import os

/// Системный лог самого контейнера. Нужен ровно для одного случая: `close()` по контракту не бросает
/// (сворачивание обязано дойти до конца и погасить остальных), но и молчать о недогашенном бине
/// нельзя — иначе утечка проходит бесследно. Уровень `.fault`: это дефект в `destroy()` бина.
///
/// Подсистема — сам фреймворк, не приложение: SwiftContext о продукте не знает.
enum ContextLog {
    private static let lifecycle = Logger(subsystem: "SwiftContext", category: "Lifecycle")

    static func destroyFailed(name: String, error: Error) {
        lifecycle.fault("destroy() бина \(name, privacy: .public) бросил: \(error, privacy: .public)")
    }
}
