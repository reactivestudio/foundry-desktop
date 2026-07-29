import Bootstrap
import SwiftUI

@main
struct FoundryApp: App {
    // Bootstrap приложения — в таргете Bootstrap (наш аналог Spring Boot): там
    // SwiftContext связывает порты с реализациями и там же собран корневой вид
    // `FoundryApplicationView` (резолв стора + сшивка контекстов). App-слой линкует
    // ровно один продукт `Bootstrap` и не знает ни вендора, ни инфраструктуры,
    // ни одного контекста поимённо.
    var body: some Scene {
        WindowGroup {
            Bootstrap.makeRootView()
        }
        .windowStyle(.automatic)
        // НЕ .contentSize: иначе окно = контент + нативный титлбар(28) сверх, и
        // онбординг-окно выходит выше макета (720×880 — это ПОЛНЫЙ размер с 44px
        // титлбаром внутри, как .ob-win). Размер держит WindowConfigurator явным
        // setFrame, содержимое заполняет кадр целиком.
        .windowResizability(.automatic)
    }
}
