import Run
import SparkIoC
import SwiftUI

/**
 Прикладной класс приложения — аналог `@SpringBootApplication`-класса `FooApplication` из
 `SpringApplication.run(FooApplication.self)`. Фреймворковый раннер `SparkApplication.run` (наш
 `SpringApplication.run`) generic и о продукте не знает; знание про ЭТО приложение — свои пакеты,
 свой корневой вид — живёт здесь. Единственное место, которому позволено касаться контейнера: держит
 контекст приватно и отдаёт App-слою ГОТОВЫЙ корневой вид (IoC, а не Service Locator — App знает лишь
 «дай корень», без `getBean`).

 Контекст строится единожды на процесс (ленивый `static let`) из ЕДИНОГО источника
 `BeanScan.definitions()` (скан `@Component` и его специализаций по слоям + подмешанные
 `@Configuration`; плагин генерит `BeanScan` на сборке — наш `@ComponentScan` по всем пакетам). Не
 собрался — падаем на старте (fail-fast).

 Корневой стор `RunStore` — тоже бин (`@Store`): контейнер строит его сам со всеми зависимостями,
 `rootView` лишь резолвит его и втыкает в корневой вид. Конкретика `FoundryApplicationView` — это
 app-specific сшивка контекстов (гейт онбординга поверх консоли), её дом — здесь, в корне композиции:
 контейнер собирает СТОР, а вид женится на сторе на границе. Направление зависимости `View → Store`
 (вид держит стор, не наоборот); резолв в корне — это по-прежнему IoC (стор получил зависимости через
 конструктор, `getBean` не расползается в прикладной код).

 Неймспейс (`enum` без инстанса) — не сущность со временем жизни, а точка входа: состояние нулевое,
 наружу торчит только `rootView`. `@MainActor`: контекст и корневой стор резолвятся на главном акторе
 (`RunStore`/`RunService` — `@MainActor`-бины, их конструктор изолирован).
 */
@MainActor
public enum FoundryApplication {
    /// Контекст, поднятый `SparkApplication.run` — один на процесс, строится при первом `rootView()`.
    /// Тип — `ConfigurableApplicationContext`: этот корень контекст поднял, значит он же им и владеет
    /// (`refresh`/`close`). Наружу не течёт ни в каком виде.
    private static let context: ConfigurableApplicationContext = build()

    /// Корневой вид с резолвнутым из контейнера стором: контейнер собрал `RunStore` (`@Store`) со
    /// всеми зависимостями, bootstrap лишь втыкает его в вид. App-слой зовёт только это.
    public static func rootView() -> some View {
        FoundryApplicationView(store: bean(ofType: RunStore.self))
    }

    /// Поднять контекст из `BeanScan.definitions()` через `SparkApplication.run`. Fail-fast:
    /// несобравшийся граф — ошибка старта, падаем громко.
    private static func build() -> ConfigurableApplicationContext {
        do {
            return try SparkApplication.run(definitions: BeanScan.definitions())
        } catch {
            fatalError("DI: контейнер не собрался: \(error)")
        }
    }

    /// Форс-резолв для точки входа: незарегистрированный/несобираемый бин — ошибка bootstrap'а,
    /// падать сразу и громко (аналог прежнего `resolve(...)!`).
    private static func bean<T>(ofType type: T.Type) -> T {
        do {
            return try context.getBean(ofType: type)
        } catch {
            fatalError("DI: не собрать \(type): \(error)")
        }
    }
}
