import Run
import Setting
import Swinject

/// Корень композиции приложения — наш аналог Spring `@Configuration`. Единственный
/// слой, который видит все контексты сразу: связывает их порты (`Run`, `Setting`)
/// с конкретными реализациями через Swinject-контейнер. Приложение линкует только
/// этот продукт (корневой вид `FoundryApplicationView` — здесь же) и не знает ни
/// одной реализации портов, ни одного контекста поимённо.
///
/// `@MainActor`: контейнер и резолв заперты на главном акторе — тот же актор, на
/// котором живёт доменный `@MainActor RunStore`, так что сборка идёт без пересечения
/// изоляции.
@MainActor
public final class AppContainer {
    public static let shared = AppContainer()

    private let resolver: Resolver

    private init() {
        let assembler = Assembler([FoundryAssembly()])
        resolver = assembler.resolver
    }

    /// Собрать стор одного рана: резолвит порты из контейнера, строит сценарий
    /// `RunService` (на главном акторе — он `@MainActor`) и тонкий `RunStore`.
    /// Force-unwrap намеренно: незарегистрированный порт — ошибка конфигурации
    /// корня композиции, и падать надо сразу и громко.
    public func makeRunStore() -> RunStore {
        let runService = RunService(
            runner: resolver.resolve(AgentRunner.self)!,
            sessionOpener: resolver.resolve(AgentSessionOpening.self)!
        )
        return RunStore(runService: runService, toolSetting: resolver.resolve(ToolService.self)!)
    }
}

/// Сборка «бинов»: каждый порт → его продакшн-реализация. Смена вендора или
/// инфраструктуры — правка одной строки здесь; домен и UI не трогаются (OCP).
struct FoundryAssembly: Assembly {
    func assemble(container: Container) {
        container.register(AgentRunner.self) { _ in ClaudeRunner() }
        container.register(AgentSessionOpening.self) { _ in ClaudeDesktopSessionOpener() }
        container.register(ToolRepository.self) { _ in UserDefaultsToolRepository() }
        container.register(ToolService.self) { resolver in
            ToolService(repository: resolver.resolve(ToolRepository.self)!)
        }
    }
}
