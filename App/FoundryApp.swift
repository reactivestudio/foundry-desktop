import FoundryFeatures
import SwiftUI

@main
struct FoundryApp: App {
    var body: some Scene {
        WindowGroup {
            FoundryRootView()
        }
        .windowStyle(.automatic)
        // НЕ .contentSize: иначе окно = контент + нативный титлбар(28) сверх, и
        // онбординг-окно выходит выше макета (720×880 — это ПОЛНЫЙ размер с 44px
        // титлбаром внутри, как .ob-win). Размер держит WindowConfigurator явным
        // setFrame, содержимое заполняет кадр целиком.
        .windowResizability(.automatic)
    }
}
