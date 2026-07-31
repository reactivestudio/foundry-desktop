import SparkIoC

/**
 Прикладная служба разрешений ОС (слой Application). Транзакции здесь нет и быть не может:
 состояние разрешений принадлежит системе, приложение его не меняет и не хранит — оно
 спрашивает. Потому служба тонкая: собирает ответы порта в доменные `Permission` и знает
 ровно одно правило — какие виды разрешений вообще существуют у приложения
 (`PermissionKind.allCases`), чтобы экран не перечислял их сам.

 `@MainActor`: службу зовёт стор с главного актора, а системный вопрос всё равно упирается
 в UI (диалог macOS). `@ApplicationService` — операций две; порта у службы нет, её резолвят
 по конкретному типу.
 */
@MainActor
@ApplicationService
public final class PermissionService {
    private let gateway: PermissionGateway

    public init(gateway: PermissionGateway) {
        self.gateway = gateway
    }

    /// Все разрешения приложения с их нынешним состоянием — в порядке `PermissionKind`.
    public func permissions() async -> [Permission] {
        var permissions: [Permission] = []
        for kind in PermissionKind.allCases {
            permissions.append(Permission.of(kind: kind, status: await gateway.status(of: kind)))
        }

        return permissions
    }

    /// Попросить доступ и вернуть разрешение с состоянием после ответа системы.
    public func request(kind: PermissionKind) async -> Permission {
        Permission.of(kind: kind, status: await gateway.request(kind: kind))
    }
}
