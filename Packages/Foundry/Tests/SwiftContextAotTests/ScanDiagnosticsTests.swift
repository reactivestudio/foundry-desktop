import SwiftContextAot
import Testing

/// Скан НЕ МОЛЧИТ: то, что выглядит рабочей аннотацией, но бином не станет, обязано всплыть здесь —
/// иначе оно всплывёт `noSuchBeanDefinition` в другом конце графа, где причину уже не видно.
/// Плюс конфайнмент главного актора: он расползается по графу зависимостей, иначе жадная
/// преинстанциация полезла бы строить `@MainActor`-бин на негарантированном акторе.
@Suite("Диагностика скана и конфайнмент главного актора")
struct ScanDiagnosticsTests {
    // MARK: - Конфайнмент главного актора расползается по графу

    @Test("Не-@MainActor бин с @MainActor-зависимостью тоже уходит из жадной сборки (транзитивно)")
    func mainActorConfinementSpreadsThroughGraph() {
        let source = """
        @MainActor @Store final class RunStore {}
        @ApplicationService final class Audit {
            init(store: RunStore) {}
        }
        @ApplicationService final class Reporter {
            init(audit: Audit) {}
        }
        @ApplicationService final class Untouched {}
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Run", text: source)])
        let confined = Dictionary(uniqueKeysWithValues: beans.map { ($0.name, $0.isMainActorConfined) })

        // Прямая зависимость и зависимость ЧЕРЕЗ неё — обе confined: иначе жадная преинстанциация
        // полезла бы строить @MainActor-бин на негарантированном акторе и уронила бы процесс трапом.
        #expect(confined == ["runStore": true, "audit": true, "reporter": true, "untouched": false])
        // Сам не @MainActor — значит свой конструктор зовём без assumeIsolated, но жадности нет.
        let audit = beans.first { $0.name == "audit" }
        #expect(audit?.isMainActor == false)
        let code = BeanRegistrationsAotContribution()
            .generateCode(for: beans, configurations: [], typeModules: [:])
        #expect(code.contains("beanType: Audit.self, scope: .singleton, isMainActorConfined: true, "))
        #expect(code.contains("{ context in Audit(store: try context.getBean(ofType: RunStore.self)) }"))
    }

    // MARK: - @Lazy/@Primary: воля автора доезжает до определения бина

    @Test("@Lazy и @Primary со скана доезжают до BeanDefinition в генерате")
    func scanCarriesLazyAndPrimary() {
        let source = """
        @Lazy @Repository struct SlowRepository {}
        @Primary @Repository struct FastRepository {}
        @Repository struct PlainRepository {}
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Setting", text: source)])
        let byName = Dictionary(uniqueKeysWithValues: beans.map { ($0.name, $0) })

        #expect(byName["slowRepository"]?.isLazyInit == true)
        #expect(byName["slowRepository"]?.isPrimary == false)
        #expect(byName["fastRepository"]?.isPrimary == true)
        #expect(byName["fastRepository"]?.isLazyInit == false)
        #expect(byName["plainRepository"]?.isLazyInit == false)
        #expect(byName["plainRepository"]?.isPrimary == false)

        // Метки в генерате обязаны идти в порядке параметров `BeanDefinition.init` — иначе не соберётся.
        let code = BeanRegistrationsAotContribution()
            .generateCode(for: beans, configurations: [], typeModules: [:])
        #expect(code.contains("beanType: SlowRepository.self, scope: .singleton, isLazyInit: true, targetTypes:"))
        #expect(code.contains("beanType: FastRepository.self, scope: .singleton, isPrimary: true, targetTypes:"))
        #expect(code.contains("beanType: PlainRepository.self, scope: .singleton, targetTypes:"))
    }

    // MARK: - Диагностика: скан не молчит

    @Test("@Component/@Configuration на enum — ошибка сборки, а не тишина")
    func reportsStereotypeOnEnum() {
        let source = """
        @Configuration
        public enum SettingConfiguration {}
        @Store
        public enum Weird {}
        """

        let scanner = ClassPathBeanDefinitionScanner()
        let beans = scanner.scan(sources: [(module: "Setting", text: source)])

        #expect(beans.isEmpty)
        #expect(scanner.configurations.isEmpty)
        #expect(scanner.problems.count == 2)
        #expect(scanner.problems.contains { $0.subject == "Weird" && $0.reason.contains("@Store") })
        #expect(scanner.problems.contains { $0.subject == "SettingConfiguration" })
    }

    @Test("Несколько init'ов без @Autowired — ошибка, а не догадка по числу параметров")
    func reportsAmbiguousInitializers() {
        let source = """
        @UseCase
        final class Foo {
            init(runner: AgentRunner) {}
            init(title: String, subtitle: String, count: Int) {}
        }
        """

        let scanner = ClassPathBeanDefinitionScanner()
        let beans = scanner.scan(sources: [(module: "Run", text: source)])

        #expect(beans.first?.dependencies.isEmpty == true)
        #expect(scanner.problems.count == 1)
        #expect(scanner.problems.first?.reason.contains("@Autowired") == true)
    }

    @Test("@Autowired выбирает конструктор внедрения независимо от числа параметров")
    func autowiredPicksInjectionInitializer() {
        let source = """
        @UseCase
        final class Foo {
            @Autowired init(runner: AgentRunner) {}
            init(title: String, subtitle: String, count: Int) {}
        }
        """

        let scanner = ClassPathBeanDefinitionScanner()
        let beans = scanner.scan(sources: [(module: "Run", text: source)])

        #expect(scanner.problems.isEmpty)
        #expect(beans.first?.dependencies == [DependencyDescriptor(label: "runner", type: "AgentRunner")])
    }

    @Test("Два бина под одним именем — ошибка сборки (имя это ключ реестра)")
    func reportsDuplicateBeanNames() {
        let scanner = ClassPathBeanDefinitionScanner()
        _ = scanner.scan(sources: [
            (module: "Run", text: "@Component struct Gateway {}"),
            (module: "Setting", text: "@Component(name: \"gateway\") struct Other {}"),
        ])

        #expect(scanner.problems.count == 1)
        #expect(scanner.problems.first?.subject == "gateway")
    }

    @Test("Одноимённые типы из двух модулей — ошибка сборки, а не молчаливая догадка")
    func reportsAmbiguousTypeNames() {
        let scanner = ClassPathBeanDefinitionScanner()
        _ = scanner.scan(sources: [
            (module: "Run", text: "@Component struct Config {}"),
            (module: "Setting", text: "@Component(name: \"settingConfig\") struct Config {}"),
        ])

        #expect(scanner.problems.contains { $0.reason.contains("объявлен в модулях Run, Setting") })
    }
}
