/// Доменные события одного рана `claude -p` — то, что показывает лента.
/// Слой домена не знает ни про JSON, ни про подпроцессы: маппинг из
/// stream-json — обязанность FoundryCLI.
public enum ClaudeEvent: Sendable, Equatable {
    case sessionStarted(SessionInit)
    /// Начался новый контент-блок — лента открывает новую карточку.
    case blockStarted(BlockKind)
    case thinkingDelta(String)
    case textDelta(String)
    case toolUse(name: String, inputSummary: String)
    case toolResult(summary: String, isError: Bool)
    case finished(RunResult)
    /// Неизвестный тип события не должен ронять ран (practices 06 §2.4).
    case unknown(type: String)
}

public enum BlockKind: Sendable, Equatable {
    case thinking
    case text
}

public struct SessionInit: Sendable, Equatable {
    public let sessionID: String
    public let model: String
    public let cwd: String

    public init(sessionID: String, model: String, cwd: String) {
        self.sessionID = sessionID
        self.model = model
        self.cwd = cwd
    }
}

public struct RunResult: Sendable, Equatable {
    public let text: String
    public let isError: Bool
    public let durationMS: Int
    public let costUSD: Double?
    public let turns: Int
    public let sessionID: String

    public init(
        text: String,
        isError: Bool,
        durationMS: Int,
        costUSD: Double?,
        turns: Int,
        sessionID: String
    ) {
        self.text = text
        self.isError = isError
        self.durationMS = durationMS
        self.costUSD = costUSD
        self.turns = turns
        self.sessionID = sessionID
    }
}

/// Режим разрешений headless-рана. В `default` без интерактива claude
/// молча отклоняет правки, поэтому дефолт прототипа — `acceptEdits`.
public enum PermissionMode: String, Sendable, CaseIterable, Identifiable {
    case `default`
    case acceptEdits
    case bypassPermissions

    public var id: String { rawValue }
}
