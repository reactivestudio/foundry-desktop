import FoundryFeatures
import SwiftUI

@main
struct FoundryApp: App {
    @State private var store = RunStore()

    var body: some Scene {
        WindowGroup {
            RunConsoleView()
                .environment(store)
        }
        .windowStyle(.automatic)
    }
}
