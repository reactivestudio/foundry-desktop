import Run
import Setting
import SwiftContext
import SwiftUI

/**
 Bootstrap приложения (наш аналог Spring Boot) — единственное место, которому позволено
 касаться контейнера. Приватно держит собранный `ApplicationContext` и раздаёт готовые объекты
 через конструкторы. Наружу — типизированные фабрики (`makeRunStore`), а НЕ generic `getBean`:
 прикладной код зависимости не «достаёт», значит это IoC, а не Service Locator.

 Неймспейс (`enum` без инстанса) — не сущность со временем жизни, а точка сборки: состояние
 её нулевое, наружу торчат только фабрики. `@MainActor`: сборка `@MainActor`-стора рана идёт
 на главном акторе — там же его сценарий и стоки.
 */
@MainActor
public enum Bootstrap {
    /// Контейнер собран из двух источников, ровно как в Spring: скан `@Component`-адаптеров
    /// (`BeanScan.definitions()` — плагин генерит его на сборке, аналог `@ComponentScan`) плюс
    /// `@Configuration`-фабрики (`SettingConfiguration().definitions()`) для бинов, которым скан
    /// не подходит (константы/много init'ов). Сборку инкапсулирует сам контекст: регистрацию
    /// окружения, заливку определений и жадную преинстанциацию делает `refresh` внутри контекста,
    /// bootstrap лишь отдаёт ему источники определений.
    private static let context: AnnotationConfigApplicationContext = {
        do {
            return try AnnotationConfigApplicationContext(
                definitions: BeanScan.definitions() + SettingConfiguration().definitions())
        } catch {
            fatalError("DI: контейнер не собрался: \(error)")
        }
    }()

    /// Корневой вид, собранный целиком: bootstrap строит стор и ВТАЛКИВАЕТ его в вид через
    /// конструктор (вид зависимость не добывает). Наружу (App-слой) торчит только это — App
    /// знает лишь «дай собранный корень», не зная ни стора, ни контекстов поимённо.
    public static func makeRootView() -> some View {
        FoundryApplicationView(store: makeRunStore())
    }

    /// Построить стор одного рана: резолвит порты, собирает сценарий `RunService` и тонкий
    /// `RunStore`. Один стор на окно (время жизни окна).
    private static func makeRunStore() -> RunStore {
        let runService = RunService(
            runner: bean(ofType: AgentRunner.self),
            sessionOpener: bean(ofType: AgentSessionOpening.self)
        )

        return RunStore(runService: runService, toolSetting: bean(ofType: ToolService.self))
    }

    /// Форс-резолв для точки сборки: незарегистрированный/несобираемый бин — ошибка bootstrap'а,
    /// падать сразу и громко (аналог прежнего `resolve(...)!`).
    private static func bean<T>(ofType type: T.Type) -> T {
        do {
            return try context.getBean(ofType: type)
        } catch {
            fatalError("DI: не собрать \(type): \(error)")
        }
    }
}
