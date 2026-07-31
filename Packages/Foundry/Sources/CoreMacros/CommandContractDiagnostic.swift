import SwiftDiagnostics

/// Диагностики классовой `@Invariants` — по одной на нарушаемое правило.
enum CommandContractDiagnostic: String, DiagnosticMessage {
    /// Метод одновременно команда и запрос: проверку инвариантов вешать некуда, молчать нельзя.
    case mixedCommandAndQuery

    var message: String {
        switch self {
        case .mixedCommandAndQuery:
            """
            Метод возвращает значение и при этом меняет состояние — по CQS это команда \
            и запрос сразу. Разделить на два метода либо, если разделить нельзя, \
            пометить проверку инвариантов явно: @Invariant.
            """
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "CoreMacros", id: rawValue)
    }

    var severity: DiagnosticSeverity {
        .error
    }
}
