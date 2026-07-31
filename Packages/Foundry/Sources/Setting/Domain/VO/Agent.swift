import Core

/**
 Выбранный агент — группа-VO агрегата `Preference`. В настройках лежит именно ВЫБОР
 (какой агент гоняет стадии), а не факт установки: установленность принадлежит системе и
 живёт в агрегате `Tool` за портом. Разведены они намеренно — выбор переживает удаление
 CLI и возвращается, когда инструмент поставят снова.

 `nil` — агент ещё не выбран: первый запуск, мастер до экрана Agent.
 */
public struct Agent: ValueObject {
    public let selected: ToolId?

    private init(selected: ToolId?) {
        self.selected = selected
    }

    public static func of(selected: ToolId? = nil) -> Agent {
        Agent(selected: selected)
    }

    /// Выбрать агента — новый VO с этим выбором.
    public func change(selected: ToolId) -> Agent {
        Agent(selected: selected)
    }
}
