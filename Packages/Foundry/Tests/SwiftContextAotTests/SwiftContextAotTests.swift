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
            ScannedGenericBeanDefinition(
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
        let beans = [ScannedGenericBeanDefinition(
            module: "Setting", concreteType: "Car", name: "car",
            targetTypes: ["Car", "Vehicle"],
            dependencies: [DependencyDescriptor(label: "engine", type: "Engine")]
        )]

        let code = BeanRegistrationsAotContribution()
            .generateCode(for: beans, configurations: [], typeModules: [:])

        #expect(code.contains("static func definitions() -> [BeanDefinitionHolder]"))
        #expect(code.contains("BeanDefinitionHolder(name: \"car\", definition: BeanDefinition("))
        #expect(code.contains("beanType: Car.self, scope: .singleton"))
        #expect(code.contains("targetTypes: [Car.self, Vehicle.self]"))
        #expect(code.contains("{ context in Car(engine: try context.getBean(ofType: Engine.self)) }"))
    }

    @Test("definitions(): бин без зависимостей — supplier без контекста")
    func generatesDependencyFreeSupplier() {
        let beans = [ScannedGenericBeanDefinition(
            module: "Run", concreteType: "ClaudeRunner", name: "claudeRunner",
            targetTypes: ["ClaudeRunner", "AgentRunner"]
        )]

        let code = BeanRegistrationsAotContribution()
            .generateCode(for: beans, configurations: [], typeModules: [:])

        #expect(code.contains("instanceSupplier: { _ in ClaudeRunner() }"))
    }

    @Test("Скан находит @Configuration; генерат подмешивает его definitions() и импортит модуль")
    func scanFoldsConfiguration() {
        let source = """
        @Configuration
        public struct SettingConfiguration {}
        """

        let scanner = ClassPathBeanDefinitionScanner()
        let beans = scanner.scan(sources: [(module: "Setting", text: source)])
        let code = BeanRegistrationsAotContribution().generateCode(
            for: beans,
            configurations: scanner.configurations,
            typeModules: scanner.moduleForType
        )

        #expect(scanner.configurations == [
            ScannedConfiguration(module: "Setting", concreteType: "SettingConfiguration"),
        ])
        #expect(beans.isEmpty) // сам конфиг бином не регистрируется — только его @Bean-фабрики
        #expect(code.contains("definitions += Setting.SettingConfiguration().definitions()"))
        #expect(code.contains("import Setting"))
    }

    @Test("Импорт модуля типа, помянутого в targetTypes из чужого контекста")
    func importsModulesOfMentionedTypes() {
        let beans = [ScannedGenericBeanDefinition(
            module: "Setting", concreteType: "Repo", name: "repo",
            targetTypes: ["Repo", "PlistRepository<PreferenceSnapshot>"]
        )]

        let code = BeanRegistrationsAotContribution().generateCode(
            for: beans,
            configurations: [],
            typeModules: ["PlistRepository": "Core", "PreferenceSnapshot": "Setting", "Repo": "Setting"]
        )

        #expect(code.contains("import Core"))
        #expect(code.contains("import Setting"))
    }

    // MARK: - Стереотипы и @MainActor

    @Test("Скан подхватывает все специализации @Component наравне с ним самим")
    func scanRecognizesStereotypes() {
        let source = """
        @DomainService struct PricingPolicy {}
        @ApplicationService final class ToolService {}
        @UseCase final class FinishOnboarding {}
        @Repository struct PreferencePlistRepository {}
        @Store final class RunStore {}
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Run", text: source)])

        // Стереотип для читателя (слой и роль), контейнеру они равны — все пять стали бинами.
        #expect(Set(beans.map(\.name)) == [
            "pricingPolicy", "toolService", "finishOnboarding", "preferencePlistRepository", "runStore",
        ])
    }

    @Test("@MainActor-бин: помечен isMainActor, генерат исключает из жадной сборки и зовёт assumeIsolated")
    func scanAndGenerateMainActorBean() {
        let source = """
        @MainActor @Store final class RunStore {
            init(service: RunService) {}
        }
        """

        let beans = ClassPathBeanDefinitionScanner().scan(sources: [(module: "Run", text: source)])
        #expect(beans.first?.isMainActor == true)

        let code = BeanRegistrationsAotContribution()
            .generateCode(for: beans, configurations: [], typeModules: [:])

        #expect(code.contains("scope: .singleton, isMainActorConfined: true, "))
        #expect(code.contains("{ context in nonisolated(unsafe) let context = context; "
            + "return try MainActor.assumeIsolated { RunStore(service: "
            + "try context.getBean(ofType: RunService.self)) } }"))
    }

    @Test("@MainActor-бин без зависимостей: assumeIsolated без контекста, без unsafe")
    func generatesMainActorDependencyFreeSupplier() {
        let beans = [ScannedGenericBeanDefinition(
            module: "Run", concreteType: "Clock", name: "clock",
            isMainActor: true, targetTypes: ["Clock"]
        )]

        let code = BeanRegistrationsAotContribution()
            .generateCode(for: beans, configurations: [], typeModules: [:])

        #expect(code.contains("instanceSupplier: { _ in MainActor.assumeIsolated { Clock() } }"))
    }

    // MARK: - Квалификация типов модулем

    @Test("Типы в генерате квалифицированы модулем объявления, включая дженерик-аргументы")
    func qualifiesEmittedTypesWithModule() {
        let beans = [ScannedGenericBeanDefinition(
            module: "Setting", concreteType: "Repo", name: "repo",
            targetTypes: ["Repo", "PlistRepository<PreferenceSnapshot>"],
            dependencies: [DependencyDescriptor(label: "encoder", type: "PropertyListEncoder")]
        )]

        let code = BeanRegistrationsAotContribution().generateCode(
            for: beans,
            configurations: [],
            typeModules: ["Repo": "Setting", "PlistRepository": "Core", "PreferenceSnapshot": "Setting"]
        )

        #expect(code.contains("beanType: Setting.Repo.self"))
        #expect(code.contains("targetTypes: [Setting.Repo.self, Core.PlistRepository<Setting.PreferenceSnapshot>.self]"))
        // Незнакомый скану тип (Foundation) остаётся как написан.
        #expect(code.contains("try context.getBean(ofType: PropertyListEncoder.self)"))
    }
}
