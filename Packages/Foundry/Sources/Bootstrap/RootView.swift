import Onboarding
import Run
import SwiftUI

/// Корневой вид приложения — композиция контекстов, живёт в таргете `Bootstrap`
/// (наш аналог Spring Boot). Держит стор рана (`@State` — время жизни окна) и
/// вставляет консоль Run под гейт онбординга. Стор НЕ добывает сам, а получает
/// его в `init` от bootstrap'а (инъекция сверху, не вытягивание) — про контейнер
/// и его фабрики вид не знает вовсе.
struct FoundryApplicationView: View {
    // Стор владеется видом (модель времени жизни SwiftUI — @State на окно), но
    // ПРИХОДИТ извне: bootstrap собрал и втолкнул. Инъекция вниз через
    // environment: гейт онбординга к нему безразличен, консоль Run — читает.
    @State private var store: RunStore

    init(store: RunStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        OnboardingGateView {
            RunConsoleView()
        }
        .environment(store)
    }
}
