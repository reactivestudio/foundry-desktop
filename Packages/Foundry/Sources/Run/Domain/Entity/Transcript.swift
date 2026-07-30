import Foundation

/// Один элемент транскрипта рана. Дельты одного контент-блока копятся в одном
/// элементе; новый блок открывает новый элемент. `body` — это текст записи;
/// КАКОЙ именно (формулировка, локализация) — решает Presentation и передаёт
/// готовым: домен относится к тексту как к непрозрачному содержимому записи.
public struct TranscriptItem: Identifiable, Sendable {
    public enum Kind: Sendable, Equatable {
        case info
        case thinking
        case text
        case tool(name: String)
    }

    public let id: Int
    public let kind: Kind
    public var body: String
    /// Для тулов: результат вызова (появляется позже отдельным событием).
    public var toolResult: String?
    public var isError: Bool

    public init(id: Int, kind: Kind, body: String, toolResult: String? = nil, isError: Bool = false) {
        self.id = id
        self.kind = kind
        self.body = body
        self.toolResult = toolResult
        self.isError = isError
    }
}

/// Транскрипт одного рана — доменный агрегат: лента элементов, старт сессии и
/// финальный результат. Инкапсулирует правила сборки ленты (открыть элемент,
/// дописать дельту к последнему, привязать результат тула к последнему открытому
/// тулу, дедуп неизвестных типов) и владеет монотонным счётчиком id.
///
/// Чистое доменное значение: без Foundation-побочек, без UI и таймингов.
/// Кадровый коалессинг дельт (когда именно дописывать) — забота Presentation;
/// сюда приходит уже накопленная строка через `appendDelta`.
public struct Transcript: Sendable {
    public private(set) var items: [TranscriptItem] = []
    public private(set) var session: SessionStart?
    public private(set) var result: RunResult?

    /// Монотонный id: НЕ сбрасывается между ранами — стабильность идентичности
    /// элементов (например, для диффинга списка в UI) держится сквозь `reset`.
    private var nextItemID = 0
    private var reportedUnknownTypes: Set<String> = []

    public init() {}

    /// Новый ран: очистить ленту, сессию, результат и дедуп неизвестных типов.
    /// Счётчик id намеренно сохраняется (см. `nextItemID`).
    public mutating func reset() {
        items = []
        session = nil
        result = nil
        reportedUnknownTypes = []
    }

    /// Запомнить старт сессии.
    public mutating func beginSession(start: SessionStart) {
        session = start
    }

    /// Завершить транскрипт финальным результатом рана.
    public mutating func complete(runResult: RunResult) {
        result = runResult
    }

    /// Открыть новый элемент ленты заданного вида с готовым текстом.
    public mutating func append(kind: TranscriptItem.Kind, body: String) {
        nextItemID += 1
        items.append(TranscriptItem(id: nextItemID, kind: kind, body: body))
    }

    /// Дописать накопленную дельту к последнему элементу; если лента пуста —
    /// открыть текстовый блок (дельта пришла раньше своего `blockStarted`).
    public mutating func appendDelta(delta: String) {
        guard !delta.isEmpty else { return }
        if items.isEmpty {
            append(kind: .text, body: delta)
        } else {
            items[items.count - 1].body += delta
        }
    }

    /// Привязать результат тула к последнему tool-элементу, у которого его ещё нет.
    /// Пустой результат замещается плейсхолдером (текст даёт Presentation).
    public mutating func attachToolResult(summary: String, isError: Bool, emptyPlaceholder: String) {
        guard
            let index = items.lastIndex(where: {
                if case .tool = $0.kind { return $0.toolResult == nil }
                return false
            })
        else { return }
        items[index].toolResult = summary.isEmpty ? emptyPlaceholder : summary
        items[index].isError = isError
    }

    /// Отметить неизвестный тип события. Возвращает `true`, если тип встречен
    /// впервые (значит, о нём стоит завести запись; повторы схлопываются).
    public mutating func noteUnknownType(type: String) -> Bool {
        reportedUnknownTypes.insert(type).inserted
    }
}
