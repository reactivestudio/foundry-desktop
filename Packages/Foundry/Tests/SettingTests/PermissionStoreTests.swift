import Testing

@testable import Setting

/// `PermissionStore` — контроллер экрана разрешений. Своего «выдано» он не держит:
/// показывает ответ системы и умеет спросить её заново. Проверяем стартовое состояние
/// (до ответа — не «всё выдано»), перечитывание и запрос.
@Suite("PermissionStore")
@MainActor
struct PermissionStoreTests {

    private func makeStore(gateway: StubPermissionGateway) -> PermissionStore {
        PermissionStore(service: PermissionService(gateway: gateway))
    }

    @Test("До первого ответа системы снимок пуст и «всё выдано» не срабатывает")
    func emptySnapshotIsNotGranted() {
        let store = makeStore(gateway: StubPermissionGateway())

        #expect(store.permissions.isEmpty)
        #expect(store.allGranted == false)
        #expect(store.status(of: .notifications) == .notDetermined)
    }

    @Test("refresh приносит состояния всех видов")
    func refreshReadsEveryKind() async {
        let gateway = StubPermissionGateway()
        gateway.statuses = [.notifications: .granted]
        let store = makeStore(gateway: gateway)

        await store.refresh()

        #expect(store.status(of: .notifications) == .granted)
        #expect(store.status(of: .accessibility) == .notDetermined)
        #expect(store.allGranted == false)
    }

    @Test("Запрос выдаёт разрешение и перечитывает состояния целиком")
    func requestGrantsAndRefreshes() async {
        let gateway = StubPermissionGateway()
        let store = makeStore(gateway: gateway)

        await store.request(kind: .notifications)
        #expect(store.status(of: .notifications) == .granted)
        #expect(store.allGranted == false)  // второе разрешение ещё не выдано

        // Универсальный доступ выдан мимо приложения — в Системных настройках.
        gateway.statuses[.accessibility] = .granted
        await store.refresh()

        #expect(store.allGranted)
    }

    @Test("Отказ виден как отказ, а не как «ещё не спрашивали»")
    func deniedIsVisible() async {
        let gateway = StubPermissionGateway()
        gateway.grantsOnRequest = false
        let store = makeStore(gateway: gateway)

        await store.request(kind: .notifications)

        #expect(store.status(of: .notifications) == .denied)
        #expect(store.allGranted == false)
    }
}
