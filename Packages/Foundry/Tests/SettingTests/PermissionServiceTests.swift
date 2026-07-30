import Testing

@testable import Setting

/// `PermissionService` — тонкий сценарий над портом ОС: он не хранит статусы и не решает,
/// выдавать ли доступ. Проверяем два его обещания: полный перечень видов со свежими
/// ответами системы и запрос ровно того вида, о котором просили.
@Suite("PermissionService")
@MainActor
struct PermissionServiceTests {

    @Test("Отдаёт все виды разрешений со статусами от системы")
    func listsEveryKindWithSystemStatus() async {
        let gateway = StubPermissionGateway()
        gateway.statuses = [.notifications: .granted, .accessibility: .denied]
        let service = PermissionService(gateway: gateway)

        let permissions = await service.permissions()

        #expect(permissions.map(\.kind) == PermissionKind.allCases)
        #expect(permissions.first { $0.kind == .notifications }?.isGranted == true)
        #expect(permissions.first { $0.kind == .accessibility }?.status == .denied)
    }

    @Test("Ничего не спрошено — все виды «ещё не спрашивали»")
    func unknownKindsAreNotDetermined() async {
        let service = PermissionService(gateway: StubPermissionGateway())

        let permissions = await service.permissions()

        #expect(permissions.allSatisfy { $0.status == .notDetermined })
    }

    @Test("Запрос уходит в порт и возвращает состояние после ответа системы")
    func requestGoesThroughGateway() async {
        let gateway = StubPermissionGateway()
        let service = PermissionService(gateway: gateway)

        let granted = await service.request(kind: .accessibility)

        #expect(gateway.requested == [.accessibility])
        #expect(granted.kind == .accessibility)
        #expect(granted.isGranted)
    }

    @Test("Отказ пользователя — это статус, а не ошибка")
    func deniedIsAStatus() async {
        let gateway = StubPermissionGateway()
        gateway.grantsOnRequest = false
        let service = PermissionService(gateway: gateway)

        let answer = await service.request(kind: .notifications)

        #expect(answer.status == .denied)
        #expect(answer.isGranted == false)
    }
}
