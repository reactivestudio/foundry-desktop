/**
 Строка экрана разрешений мастера: что показать (имя, пояснение), выдано ли разрешение
 и КАКОЙ вопрос системе задаёт кнопка Allow (`request` асинхронный — за ним диалог macOS).
 Собственного состояния у строки нет: `isGranted` читается из `PermissionStore`, то есть
 в конечном счёте у самой ОС. Строки собирает `PermissionsScreen`.

 Имя не `Permission` намеренно: так зовётся доменная read-модель разрешения; здесь —
 её экранная строка с текстами и намерением.
 */
struct PermissionRowModel: Identifiable {
    let id: PermissionKind
    let name: String
    let description: String
    let isGranted: Bool
    let request: () async -> Void
}
