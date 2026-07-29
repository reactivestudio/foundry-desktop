import SwiftContextAot
import Testing

@Suite("SwiftContextAot")
struct SwiftContextAotTests {
    @Test("Скан находит @Component: скоуп, имя по умолчанию, targetTypes из наследования")
    func scanExtractsComponent() {
        let source = """
        public protocol PreferenceRepository {}
        @Component(scope: .prototype)
        public final class PreferencePlistRepository: PreferenceRepository {}
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Setting", text: source)])

        #expect(beans == [
            ScannedBeanDefinition(
                module: "Setting",
                concreteType: "PreferencePlistRepository",
                name: "preferencePlistRepository",
                scope: "prototype",
                targetTypes: ["PreferencePlistRepository", "PreferenceRepository"]
            ),
        ])
    }

    @Test("Явное имя из @Component(name:) побеждает дефолт")
    func scanReadsExplicitName() {
        let source = """
        @Component(name: "primaryRunner")
        public struct ClaudeRunner {}
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Run", text: source)])

        #expect(beans.first?.name == "primaryRunner")
    }

    @Test("targetTypes = транзитивное замыкание всей цепочки протоколов")
    func closureWalksWholeChain() {
        let source = """
        protocol Animal {}
        protocol Pet: Animal {}
        @Component
        final class Dog: Pet {}
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Core", text: source)])

        #expect(beans.first?.targetTypes == ["Dog", "Pet", "Animal"])
    }

    @Test("Открытый дженерик-база и PAT-протокол выкинуты из targetTypes")
    func closureExcludesOpenGenericAndPAT() {
        let source = """
        open class PlistRepository<Snapshot> {}
        protocol Repository { associatedtype Aggregate }
        protocol PreferenceRepository: Repository {}
        @Component
        final class Repo: PlistRepository<Snapshot>, PreferenceRepository {}
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Setting", text: source)])

        #expect(beans.first?.targetTypes == ["Repo", "PreferenceRepository"])
    }

    @Test("Конкретная дженерик-инстанциация попадает в targetTypes целиком")
    func closureIncludesConcreteGeneric() {
        let source = """
        struct PreferenceSnapshot {}
        open class PlistRepository<Snapshot> {}
        protocol PreferenceRepository {}
        @Component
        final class Repo: PlistRepository<PreferenceSnapshot>, PreferenceRepository {}
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Setting", text: source)])

        #expect(beans.first?.targetTypes == [
            "Repo", "PlistRepository<PreferenceSnapshot>", "PreferenceRepository",
        ])
    }

    @Test("Зависимости конструктора вычитаны: метка, тип, коллекция")
    func scanReadsConstructorDependencies() {
        let source = """
        @Component
        final class Car {
            init(engine: Engine, wheels: [Wheel], _ horn: Horn) {}
        }
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Run", text: source)])

        #expect(beans.first?.dependencies == [
            DependencyDescriptor(label: "engine", type: "Engine"),
            DependencyDescriptor(label: "wheels", type: "Wheel", isCollection: true),
            DependencyDescriptor(label: nil, type: "Horn"),
        ])
    }

    @Test("Замыкание сшивается ЧЕРЕЗ файлы (контракт в одном, реализация в другом)")
    func closureSpansSources() {
        let contract = "protocol AgentRunner {}"
        let impl = """
        @Component
        struct ClaudeRunner: AgentRunner {}
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [
            (module: "Run", text: contract),
            (module: "Run", text: impl),
        ])

        #expect(beans.first?.targetTypes == ["ClaudeRunner", "AgentRunner"])
    }

    @Test("Тип без @Component не попадает в скан")
    func scanSkipsUnannotated() {
        let scanner = ClassPathBeanDefinitionScanner()
        let beans = scanner.scan(sources: [(module: "Core", text: "final class Plain {}")])

        #expect(beans.isEmpty)
    }

    @Test("moduleForType знает, где объявлен тип")
    func scannerTracksModules() {
        let scanner = ClassPathBeanDefinitionScanner()
        _ = scanner.scan(sources: [
            (module: "Core", text: "open class PlistRepository<Snapshot> {}"),
            (module: "Setting", text: "@Component struct Repo {}"),
        ])

        #expect(scanner.moduleForType["PlistRepository"] == "Core")
        #expect(scanner.moduleForType["Repo"] == "Setting")
    }

    // MARK: - Генерат definitions() (BeanDefinitionHolder для контекста)

    @Test("definitions(): имя, скоуп, targetTypes и supplier с внедрением")
    func generatesDefinitionsWithSupplier() {
        let beans = [ScannedBeanDefinition(
            module: "Setting", concreteType: "Car", name: "car",
            targetTypes: ["Car", "Vehicle"],
            dependencies: [DependencyDescriptor(label: "engine", type: "Engine")]
        )]

        let code = BeanRegistrationsCodeGenerator().generateCode(for: beans, typeModules: [:])

        #expect(code.contains("static func definitions() -> [BeanDefinitionHolder]"))
        #expect(code.contains("BeanDefinitionHolder(name: \"car\", definition: BeanDefinition("))
        #expect(code.contains("beanType: Car.self, scope: .singleton"))
        #expect(code.contains("targetTypes: [Car.self, Vehicle.self]"))
        #expect(code.contains("{ context in Car(engine: try context.getBean(ofType: Engine.self)) }"))
    }

    @Test("definitions(): бин без зависимостей — supplier без контекста")
    func generatesDependencyFreeSupplier() {
        let beans = [ScannedBeanDefinition(
            module: "Run", concreteType: "ClaudeRunner", name: "claudeRunner",
            targetTypes: ["ClaudeRunner", "AgentRunner"]
        )]

        let code = BeanRegistrationsCodeGenerator().generateCode(for: beans, typeModules: [:])

        #expect(code.contains("instanceSupplier: { _ in ClaudeRunner() }"))
    }

    @Test("Импорт модуля типа, помянутого в targetTypes из чужого контекста")
    func importsModulesOfMentionedTypes() {
        let beans = [ScannedBeanDefinition(
            module: "Setting", concreteType: "Repo", name: "repo",
            targetTypes: ["Repo", "PlistRepository<PreferenceSnapshot>"]
        )]

        let code = BeanRegistrationsCodeGenerator().generateCode(
            for: beans,
            typeModules: ["PlistRepository": "Core", "PreferenceSnapshot": "Setting", "Repo": "Setting"]
        )

        #expect(code.contains("import Core"))
        #expect(code.contains("import Setting"))
    }
}
