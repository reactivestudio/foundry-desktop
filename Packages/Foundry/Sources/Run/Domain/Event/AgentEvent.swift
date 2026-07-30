/// Доменные события одного рана агента — то, что показывает лента. Словарь
/// вендор-нейтрален: конкретный агент (сегодня — `claude -p`) поставляет их через
/// адаптер. Слой домена не знает ни про JSON, ни про подпроцессы, ни про вендора:
/// маппинг из его stream-протокола — обязанность адаптера в Infrastructure.
public enum AgentEvent: Sendable, Equatable {
    case sessionStarted(SessionStart)
    /// Начался новый контент-блок — лента открывает новую карточку.
    case blockStarted(BlockKind)
    case thinkingDelta(String)
    case textDelta(String)
    case toolUse(name: String, inputSummary: String)
    case toolResult(summary: String, isError: Bool)
    case finished(RunResult)
    /// Неизвестный тип события не должен ронять ран (practices 06, пункт 2.4).
    case unknown(type: String)
}

public enum BlockKind: Sendable, Equatable {
    case thinking
    case text
}

public struct SessionStart: Sendable, Equatable {
    public let sessionID: String
    public let model: String
    public let projectDirectory: String

    public init(sessionID: String, model: String, projectDirectory: String) {
        self.sessionID = sessionID
        self.model = model
        self.projectDirectory = projectDirectory
    }
}

public struct RunResult: Sendable, Equatable {
    public let text: String
    public let isError: Bool
    public let durationMilliseconds: Int
    public let costUSD: Double?
    public let turns: Int
    public let sessionID: String

    public init(
        text: String,
        isError: Bool,
        durationMilliseconds: Int,
        costUSD: Double?,
        turns: Int,
        sessionID: String
    ) {
        self.text = text
        self.isError = isError
        self.durationMilliseconds = durationMilliseconds
        self.costUSD = costUSD
        self.turns = turns
        self.sessionID = sessionID
    }
}

/// Режим разрешений headless-рана. В `default` без интерактива агент молча
/// отклоняет правки, поэтому дефолт прототипа — `acceptEdits`.
///
/// ДОЛГ вендор-нейтральности: сами кейсы (`acceptEdits`/`bypassPermissions`) —
/// это флаги CLI `claude`, единственная деталь вендора, оставшаяся в ядре.
/// Обобщать сейчас, против одного набора флагов, — та самая протекающая
/// абстракция; выправить, когда второй агент покажет свою модель разрешений
/// (тогда — нейтральная политика в ядре + маппинг в каждом адаптере).
///
/// Только `String` (аргумент CLI) и `Sendable` (пересечение границы задачи) —
/// ядро framework-free. Конформансы для UI (`Identifiable`/`CaseIterable` под
/// Picker) живут расширением в UI-слое, если понадобятся; сейчас Picker задаёт
/// теги руками и в них не нуждается.
public enum PermissionMode: String, Sendable {
    case `default`
    case acceptEdits
    case bypassPermissions
}
