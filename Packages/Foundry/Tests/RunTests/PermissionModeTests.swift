import Run
import Testing

@Suite("PermissionMode")
struct PermissionModeTests {
    @Test("PermissionMode передаётся в CLI своим rawValue")
    func permissionModeRawValues() {
        #expect(PermissionMode.acceptEdits.rawValue == "acceptEdits")
        #expect(PermissionMode.bypassPermissions.rawValue == "bypassPermissions")
    }
}
