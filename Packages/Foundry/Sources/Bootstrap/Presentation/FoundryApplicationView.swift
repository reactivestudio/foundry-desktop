import Board
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
    private let permissionStore: PermissionStore
    private let toolStore: ToolStore

    init(
        runStore: RunStore,
        preferenceStore: PreferenceStore,
        permissionStore: PermissionStore,
        toolStore: ToolStore
    ) {
        self.runStore = runStore
        self.preferenceStore = preferenceStore
        self.permissionStore = permissionStore
        self.toolStore = toolStore
    }

    var body: some View {
        SetupGateView(
            preferenceStore: preferenceStore,
            permissionStore: permissionStore,
            toolStore: toolStore
        ) {
            // Главный экран — доска change'ей (эталон
            // `design/candidates/main-screen-board.md`). Консоль рана сшита
            // сюда ГОСТЕМ: в рейле эталона своего раздела у неё нет, а
            // выкинуть единственную работающую функцию приложения нельзя.
            // ДОЛГ: место консоли в разделах — вопрос, который эталон не решал,
            // и «Инбокс» здесь временный приют, а не ответ.
            BoardScreenView(guestSection: .inbox) {
                RunConsoleView()
            }
        }
        .environment(runStore)
    }
}
