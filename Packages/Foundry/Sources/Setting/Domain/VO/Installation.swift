import Core

/**
 Установленность инструмента: где он лежит и какой он версии. Это, как и разрешения ОС,
 read-модель чужой истины — состояние системы пользователя, а не наше решение. Оттого VO
 неизменяем и не сохраняется: инструмент могли снести или обновить мимо приложения, и
 единственный честный способ узнать это — спросить систему заново (порт `ToolGateway`).

 «Установлен» = нашли путь. Версия отдельно и опциональна: инструмент может стоять, а
 версию не сказать (не тот флаг, чужой формат вывода) — это не повод считать его
 отсутствующим.
 */
public struct Installation: ValueObject {
    /// Путь к исполняемому файлу или каталогу установки; `nil` — инструмента нет.
    public let path: String?
    /// Версия, если её удалось узнать.
    public let version: String?

    private init(path: String?, version: String?) {
        self.path = path
        self.version = version
    }

    /// Инструмента в системе нет.
    public static let missing = Installation(path: nil, version: nil)

    /// Инструмент найден по пути; версия — если её удалось выяснить.
    public static func of(path: String, version: String? = nil) -> Installation {
        Installation(path: path, version: version)
    }

    public var isInstalled: Bool {
        path != nil
    }
}
