import Onboarding
import Run
import SwiftUI

/// Корневой вид приложения — композиция контекстов, живёт в корне композиции
/// (наш аналог Spring @Configuration). Держит стор рана (`@State` — время жизни
/// окна) и вставляет консоль Run под гейт онбординга. `.app` линкует только
/// `Configuration` и не знает ни одного контекста поимённо.
public struct FoundryApplicationView: View {
    // Стор резолвится из контейнера один раз на окно. Инъекция вниз через
    // environment: гейт онбординга к нему безразличен, консоль Run — читает.
    @State private var store = AppContainer.shared.makeRunStore()

    public init() {}

    public var body: some View {
        OnboardingGateView {
            RunConsoleView()
        }
        .environment(store)
    }
}
