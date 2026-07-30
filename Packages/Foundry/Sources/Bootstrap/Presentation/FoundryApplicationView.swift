import Onboarding
import Run
import SwiftUI

/// Корневой вид приложения — композиция контекстов, живёт в таргете `Bootstrap`
/// (наш аналог Spring Boot): вставляет консоль Run под гейт онбординга. Стор НЕ
/// добывает сам, а получает его в `init` от bootstrap'а (инъекция сверху, не
/// вытягивание) — про контейнер и его фабрики вид не знает вовсе.
struct FoundryApplicationView: View {
    // Простой `let`, а НЕ `@State`: стор не принадлежит виду — им владеет контейнер
    // (бин `@Store`, синглтон на процесс), вид лишь получил ссылку. `@State` тут врал бы
    // про владение и, обернув внешний объект, молча удержал бы ПЕРВЫЙ инстанс, если стор
    // однажды станет `.prototype`. Наблюдаемость даёт `@Observable`, а не `@State`.
    // Инъекция вниз через environment: гейт онбординга к стору безразличен, консоль Run — читает.
    private let store: RunStore

    init(store: RunStore) {
        self.store = store
    }

    var body: some View {
        OnboardingGateView {
            RunConsoleView()
        }
        .environment(store)
    }
}
