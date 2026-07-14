import FoundryCore
import Testing

@Suite("FoundryCore")
struct FoundryCoreTests {
    @Test("PermissionMode передаётся в CLI своим rawValue")
    func permissionModeRawValues() {
        #expect(PermissionMode.acceptEdits.rawValue == "acceptEdits")
        #expect(PermissionMode.bypassPermissions.rawValue == "bypassPermissions")
    }
}
