/**
 Строка экрана разрешений мастера — ВРЕМЕННАЯ презентационная модель: имя, пояснение
 и «выдано ли» (сид в `OnboardingCatalog.permissions`, мутабельное `isGranted` держит
 `OnboardingModel`). Сегодня выдача имитируется. Имя намеренно НЕ `Permission`: это
 имя занято под будущую read-модель домена — статус разрешения ОС, который приходит
 из порта-gateway и нигде не хранится.
 */
struct PermissionRowModel: Identifiable {
    let id: String
    let name: String
    let description: String
    var isGranted: Bool
}
