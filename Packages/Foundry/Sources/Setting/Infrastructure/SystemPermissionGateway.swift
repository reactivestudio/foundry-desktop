import ApplicationServices
import SparkIoC
import UserNotifications

/**
 Продакшн-адаптер порта `PermissionGateway` — настоящие механизмы macOS. Ветвление по виду
 разрешения живёт ЗДЕСЬ, потому что вид и есть выбор механизма: уведомления спрашивает
 `UNUserNotificationCenter`, универсальный доступ — `AXIsProcessTrustedWithOptions`. Дробить
 это на порт-на-вид нечего: наружу они выглядят одинаково, а внутри у них общего ровно
 столько же, сколько у любых двух системных API.

 Механизмы отвечают ПО-РАЗНОМУ, и порт этой разницы не скрывает:
 - уведомления — честный диалог с ответом «да/нет» прямо в `requestAuthorization`;
 - универсальный доступ — диалог лишь ОТКРЫВАЕТ Системные настройки, галочку ставят там,
 и `AXIsProcessTrusted()` станет `true` уже после возвращения в приложение. Потому экран
 перечитывает состояние, когда окно снова становится активным.

 Системные объекты не держит: `UNUserNotificationCenter.current()` требует настоящего
 бандла и зовётся лениво, в момент вопроса, — в тестах этот адаптер не создают вовсе,
 сценарий проверяют на заглушке порта.
 */
@Component
public struct SystemPermissionGateway: PermissionGateway {
    public init() {}

    public func status(of kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .notifications:
            await notificationStatus()
        case .accessibility:
            accessibilityStatus()
        }
    }

    public func request(kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .notifications:
            await requestNotifications()
        case .accessibility:
            promptAccessibility()
        }
    }

    // MARK: - Уведомления (UserNotifications)

    private func notificationStatus() async -> PermissionStatus {
        // Замыкание вместо `await notificationSettings()`: наружу выпускается только
        // само перечисление статуса, а не объект настроек, — он не `Sendable` и через
        // границу актора не проходит.
        let status: UNAuthorizationStatus = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }

        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        default:
            // authorized/provisional/ephemeral — уведомления показать можно.
            return .granted
        }
    }

    private func requestNotifications() async -> PermissionStatus {
        let center = UNUserNotificationCenter.current()
        let isGranted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false

        return isGranted ? .granted : .denied
    }

    // MARK: - Универсальный доступ (Accessibility)

    /// Отказа система здесь не показывает: доступа нет — значит, его ещё можно попросить
    /// (диалог откроет Системные настройки). Потому `notDetermined`, а не `denied`.
    private func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    /// Ключ опции «показать диалог» для `AXIsProcessTrustedWithOptions`. Строкой, а не
    /// `kAXTrustedCheckOptionPrompt`: та объявлена в ApplicationServices изменяемой
    /// глобальной переменной и в строгой модели конкурентности недоступна. Значение —
    /// ровно это, оно зафиксировано в `AXUIElement.h` и является частью API.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    private func promptAccessibility() -> PermissionStatus {
        let options = [Self.promptOptionKey as CFString: true] as CFDictionary

        // Возвращает состояние НА СЕЙЧАС: галочку в Системных настройках пользователь
        // поставит уже после этого вызова.
        return AXIsProcessTrustedWithOptions(options) ? .granted : .notDetermined
    }
}
