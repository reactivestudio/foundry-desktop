/// AOT-вклад: генерит исходник `enum BeanScan` для bootstrap'а вместо рантайм-рефлексии. Имя и роль —
/// как у Spring `BeanRegistrationsAotContribution` (org.springframework.beans.factory.aot): та на этапе
/// AOT пишет класс `Xxx__BeanDefinitions` с `getXxxBeanDefinition()` и `setInstanceSupplier`; мы пишем
/// `BeanScan.definitions() -> [BeanDefinitionHolder]` — найденные `@Component`-бины как ДАННЫЕ (имя,
/// скоуп, `targetTypes` = транзитивное замыкание, `instanceSupplier` — переходник к конструктору).
/// Логики резолва тут нет — её держит фабрика бинов.
///
/// Типы пишем КВАЛИФИЦИРОВАННО модулем объявления (`Core.PlistRepository<Setting.PreferenceSnapshot>`)
/// по карте `typeModules` — так одноимённые типы из разных контекстов не превращаются в
/// неоднозначность, а импорты остаются честными. Чего скан не знает (Foundation, stdlib, вложенные
/// `Foo.Bar`) — оставляем как есть.
public struct BeanRegistrationsAotContribution {
    public init() {}

    public func generateCode(
        for beans: [ScannedGenericBeanDefinition],
        configurations: [ScannedConfiguration],
        typeModules: [String: String]
    ) -> String {
        let ordered = beans.sorted { ($0.module, $0.concreteType) < ($1.module, $1.concreteType) }
        let orderedConfigs = configurations
            .sorted { ($0.module, $0.concreteType) < ($1.module, $1.concreteType) }
        let imports = importLines(for: ordered, configurations: orderedConfigs, typeModules: typeModules)
        let definitions = ordered
            .map { definition(bean: $0, typeModules: typeModules) }
            .joined(separator: ",\n")
        let configLines = orderedConfigs
            .map { "        definitions += \(qualified(type: $0.concreteType, typeModules: typeModules))().definitions()" }
            .joined(separator: "\n")

        return """
        // Сгенерировано BeanScan — не редактировать вручную. Аналог @ComponentScan.
        \(imports)

        enum BeanScan {
            static func definitions() -> [BeanDefinitionHolder] {
                var definitions: [BeanDefinitionHolder] = [
        \(definitions)
                ]
        \(configLines)
                return definitions
            }
        }
        """
    }

    /// Foundation (supplier'ы ссылаются на её типы напрямую) и SwiftContext (несёт
    /// `BeanDefinitionHolder`/`BeanDefinition`/фабрику) — всегда; плюс модуль каждого бина, модуль
    /// каждого типа, помянутого в `targetTypes`/зависимостях, и модуль каждого `@Configuration`
    /// (генерат зовёт его `Тип().definitions()`).
    private func importLines(
        for beans: [ScannedGenericBeanDefinition],
        configurations: [ScannedConfiguration],
        typeModules: [String: String]
    ) -> String {
        var modules: Set<String> = ["Foundation", "SwiftContext"]
        for bean in beans {
            modules.insert(bean.module)
            let mentioned = bean.targetTypes + bean.dependencies.map(\.type)
            for identifier in mentioned.flatMap(TypeHierarchy.identifiers) {
                if let module = typeModules[identifier] {
                    modules.insert(module)
                }
            }
        }
        for configuration in configurations {
            modules.insert(configuration.module)
        }

        return modules.sorted().map { "import \($0)" }.joined(separator: "\n")
    }

    private func definition(bean: ScannedGenericBeanDefinition, typeModules: [String: String]) -> String {
        let types = bean.targetTypes
            .map { "\(qualified(type: $0, typeModules: typeModules)).self" }
            .joined(separator: ", ")
        // Порядок меток обязан совпадать с порядком параметров `BeanDefinition.init`.
        let lazy = bean.isLazyInit ? "isLazyInit: true, " : ""
        // Требует главного актора (сам `@MainActor` или транзитивно зависит от такого) — вон из
        // жадной преинстанциации: её актор не гарантирован, а изолированный конструктор оттуда — трап.
        let confined = bean.isMainActor || bean.isMainActorConfined ? "isMainActorConfined: true, " : ""
        let primary = bean.isPrimary ? "isPrimary: true, " : ""

        return "            BeanDefinitionHolder(name: \"\(bean.name)\", definition: BeanDefinition("
            + "beanType: \(qualified(type: bean.concreteType, typeModules: typeModules)).self, "
            + "scope: .\(bean.scope), \(lazy)\(confined)\(primary)"
            + "targetTypes: [\(types)], instanceSupplier: \(supplier(bean: bean, typeModules: typeModules))))"
    }

    private func supplier(bean: ScannedGenericBeanDefinition, typeModules: [String: String]) -> String {
        let hasDependencies = !bean.dependencies.isEmpty
        let arguments = bean.dependencies
            .map { resolve(dependency: $0, typeModules: typeModules) }
            .joined(separator: ", ")
        let concrete = qualified(type: bean.concreteType, typeModules: typeModules)
        let construction = hasDependencies ? "\(concrete)(\(arguments))" : "\(concrete)()"
        guard bean.isMainActor else {
            return "{ \(hasDependencies ? "context" : "_") in \(construction) }"
        }
        // `@MainActor`-конструктор зовём через `assumeIsolated`: resolve идёт на главном акторе
        // (корень композиции `@MainActor`), а тип supplier'а фабрики неизолирован. `context` неизолирован и
        // non-Sendable — вносим его в `@MainActor`-замыкание локальным `nonisolated(unsafe)`: фабрика
        // по контракту резолвит `@MainActor`-бины только на главном акторе, внутреннего замка нет.
        guard hasDependencies else {
            return "{ _ in MainActor.assumeIsolated { \(construction) } }"
        }

        return "{ context in nonisolated(unsafe) let context = context; "
            + "return try MainActor.assumeIsolated { \(construction) } }"
    }

    private func resolve(dependency: DependencyDescriptor, typeModules: [String: String]) -> String {
        let type = qualified(type: dependency.type, typeModules: typeModules)
        let call = dependency.isCollection
            ? "Array(try context.getBeans(ofType: \(type).self).values)"
            : "try context.getBean(ofType: \(type).self)"

        return dependency.label.map { "\($0): \(call)" } ?? call
    }

    /// Тип, квалифицированный модулем объявления, рекурсивно по дженерик-аргументам:
    /// `Box<Item>` → `Run.Box<Setting.Item>`. Незнакомое скану имя остаётся как написано.
    private func qualified(type raw: String, typeModules: [String: String]) -> String {
        let base = TypeHierarchy.baseName(of: raw)
        let head = typeModules[base].map { "\($0).\(base)" } ?? base
        let arguments = TypeHierarchy.genericArguments(of: raw)
        guard !arguments.isEmpty else {
            return head
        }
        let inner = arguments
            .map { qualified(type: $0, typeModules: typeModules) }
            .joined(separator: ", ")

        return "\(head)<\(inner)>"
    }
}
