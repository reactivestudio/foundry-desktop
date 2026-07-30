import Core

/**
 Разрешение ОС: вид и его текущее состояние. Это read-модель системы, а НЕ часть агрегата
 `Preference` — приложение разрешениями не владеет и не сохраняет их, оно лишь спрашивает
 систему через порт `PermissionGateway` и показывает ответ. Оттого у типа нет ни id, ни
 команд: менять состояние может только пользователь в диалоге macOS.

 VO, а не сущность: два разрешения одного вида с одним состоянием — это одно и то же,
 различать их нечем и незачем.
 */
public struct Permission: ValueObject {
    public let kind: PermissionKind
    public let status: PermissionStatus

    private init(kind: PermissionKind, status: PermissionStatus) {
        self.kind = kind
        self.status = status
    }

    public static func of(kind: PermissionKind, status: PermissionStatus) -> Permission {
        Permission(kind: kind, status: status)
    }

    /// Можно ли пользоваться возможностью, ради которой разрешение просили.
    public var isGranted: Bool {
        status == .granted
    }
}
