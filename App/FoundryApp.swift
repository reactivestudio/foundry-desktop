import Configuration
import Presentation
import SwiftUI

@main
struct FoundryApp: App {
    // Корень композиции вынесен в Configuration (наш аналог Spring
    // @Configuration): там Swinject связывает порты с реализациями. Здесь — только
    // резолв готового стора и раздача его вниз через environment. App-слой не знает
    // ни вендора, ни инфраструктуры — лишь абстракции.
    @State private var store = AppContainer.shared.makeRunStore()

    var body: some Scene {
        WindowGroup {
            FoundryRootView()
                .environment(store)
        }
        .windowStyle(.automatic)
        // НЕ .contentSize: иначе окно = контент + нативный титлбар(28) сверх, и
        // онбординг-окно выходит выше макета (720×880 — это ПОЛНЫЙ размер с 44px
        // титлбаром внутри, как .ob-win). Размер держит WindowConfigurator явным
        // setFrame, содержимое заполняет кадр целиком.
        .windowResizability(.automatic)
    }
}
