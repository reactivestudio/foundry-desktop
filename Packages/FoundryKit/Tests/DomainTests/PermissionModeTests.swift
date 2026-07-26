import Domain
import Testing

@Suite("Domain")
struct DomainTests {
    @Test("PermissionMode передаётся в CLI своим rawValue")
    func permissionModeRawValues() {
        #expect(PermissionMode.acceptEdits.rawValue == "acceptEdits")
        #expect(PermissionMode.bypassPermissions.rawValue == "bypassPermissions")
    }
}
