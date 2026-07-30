import Run
import Setting
import SwiftUI

/// Корневой вид приложения — композиция контекстов, живёт в таргете `Bootstrap`
/// (наш аналог Spring Boot): вставляет консоль Run под гейт первичной настройки. Сторы НЕ
/// добывает сам, а получает их в `init` от bootstrap'а (инъекция сверху, не
/// вытягивание) — про контейнер и его фабрики вид не знает вовсе.
struct FoundryApplicationView: View {
    // Простые `let`, а НЕ `@State`: сторы не принадлежат виду — ими владеет контейнер
    // (бины `@Store`, синглтоны на процесс), вид лишь получил ссылки. `@State` тут врал бы
    // про владение и, обернув внешний объект, молча удержал бы ПЕРВЫЙ инстанс, если стор
    // однажды станет `.prototype`. Наблюдаемость даёт `@Observable`, а не `@State`.
    // Стор рана инъектируется вниз через environment (его читает консоль); стор настроек
    // нужен здесь же, на гейте, — его передаём прямо.
    private let runStore: RunStore
    private let preferenceStore: PreferenceStore

    init(runStore: RunStore, preferenceStore: PreferenceStore) {
        self.runStore = runStore
        self.preferenceStore = preferenceStore
    }

    var body: some View {
        OnboardingGateView(preferenceStore: preferenceStore) {
            RunConsoleView()
        }
        .environment(runStore)
    }
}
