import Observation
import SparkIoC

/**
 Стор разрешений ОС — тонкий контроллер презентационного слоя BC `Setting`, брат
 `PreferenceStore`. Разный у них не стиль, а природа данных: настройки приложение хранит,
 а разрешения только ЧИТАЕТ у системы, и потому здесь нет ни одного интента «поменять» —
 есть `refresh` (спросить заново) и `request` (попросить у системы).

 Снимок стартует пустым: спросить систему можно только асинхронно, а конструктор бина
 синхронный. Экран заполняет его первым же `refresh` — до ответа строки показывают
 «ещё не спрашивали», то есть кнопку Allow, а не ложную галочку.

 `@Store` — стереотип бина слоя Presentation; `@MainActor` — состояние экрана.
 */
@MainActor
@Observable
@Store
public final class PermissionStore {
    /// Разрешения со статусами в порядке `PermissionKind`. Пусто — ещё не спрашивали систему.
    public private(set) var permissions: [Permission] = []

    // Зависимость, не состояние: из наблюдения исключена (практики 03).
    @ObservationIgnored private let service: PermissionService

    public init(service: PermissionService) {
        self.service = service
    }

    /// Выданы ли ВСЕ разрешения. Пустой снимок (систему ещё не спрашивали) — не «всё
    /// выдано»: `allSatisfy` на пустом массиве истинен, и без этой проверки экран
    /// считал бы разрешения полученными до первого же ответа.
    public var allGranted: Bool {
        !permissions.isEmpty && permissions.allSatisfy(\.isGranted)
    }

    /// Состояние одного вида; пока снимка нет — «ещё не спрашивали».
    public func status(of kind: PermissionKind) -> PermissionStatus {
        permissions.first { permission in permission.kind == kind }?.status ?? .notDetermined
    }

    /// Перечитать состояния у системы. Зовётся при появлении экрана и каждый раз, когда
    /// окно снова становится активным: разрешение могли выдать в Системных настройках.
    public func refresh() async {
        permissions = await service.permissions()
    }

    /// Попросить у системы доступ. Ответ по этому виду разбирать отдельно не нужно —
    /// перечитываем ВСЕ виды: пока висел системный диалог, соседнее разрешение пользователь
    /// мог выдать руками.
    public func request(kind: PermissionKind) async {
        _ = await service.request(kind: kind)
        await refresh()
    }
}
