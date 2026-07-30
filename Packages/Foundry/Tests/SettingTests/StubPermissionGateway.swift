@testable import Setting

/// Заглушка порта разрешений: отдаёт заранее заданные статусы и запоминает, о чём её
/// спрашивали. Так сценарий и стор проходятся целиком, не показывая ни одного диалога
/// macOS и не трогая `UNUserNotificationCenter` (в тестовом процессе бандла нет).
///
/// `@MainActor` — как и служба, которая её зовёт; поэтому изменяемое состояние заглушки
/// безопасно и без блокировок.
@MainActor
final class StubPermissionGateway: PermissionGateway {
    /// Что отвечать на вопрос о статусе. Чего нет в словаре — «ещё не спрашивали».
    var statuses: [PermissionKind: PermissionStatus] = [:]
    /// Каким становится статус после запроса — имитация ответа пользователя в диалоге.
    var grantsOnRequest = true
    private(set) var requested: [PermissionKind] = []

    func status(of kind: PermissionKind) async -> PermissionStatus {
        statuses[kind] ?? .notDetermined
    }

    func request(kind: PermissionKind) async -> PermissionStatus {
        requested.append(kind)
        let status: PermissionStatus = grantsOnRequest ? .granted : .denied
        statuses[kind] = status

        return status
    }
}
