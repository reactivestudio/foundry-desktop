/// Генератор исходника `enum BeanScan` для bootstrap'а (аналог Spring AOT — там
/// `BeanRegistrationsAotContribution` генерит код регистрации бинов вместо рантайм-рефлексии).
/// `generateCode` отдаёт `definitions() -> [BeanDefinitionHolder]`: найденные `@Component`-бины как
/// ДАННЫЕ (имя, скоуп, `targetTypes` = транзитивное замыкание, `instanceSupplier` — переходник к
/// конструктору). Логики резолва тут нет — её держит фабрика бинов.
///
/// Импорты считаются по `typeModules` (тип → модуль объявления): поминаем в генерате тип из чужого
/// контекста (порт из Core, дженерик-аргумент из Setting) — импортируем его модуль. Так генерат
/// собирается, из какого бы контекста ни пришёл супертип или зависимость.
public struct BeanRegistrationsCodeGenerator {
    public init() {}

    public func generateCode(
        for beans: [ScannedBeanDefinition],
        typeModules: [String: String]
    ) -> String {
        let ordered = beans.sorted { ($0.module, $0.concreteType) < ($1.module, $1.concreteType) }
        let imports = importLines(for: ordered, typeModules: typeModules)
        let definitions = ordered.map(definition).joined(separator: ",\n")

        return """
        // Сгенерировано BeanScan — не редактировать вручную. Аналог @ComponentScan.
        \(imports)

        enum BeanScan {
            static func definitions() -> [BeanDefinitionHolder] {
                [
        \(definitions)
                ]
            }
        }
        """
    }

    /// Foundation (supplier'ы ссылаются на её типы напрямую) и SwiftContext (несёт
    /// `BeanDefinitionHolder`/`BeanDefinition`/фабрику) — всегда; плюс модуль каждого бина и модуль
    /// каждого типа, помянутого в `targetTypes`/зависимостях.
    private func importLines(
        for beans: [ScannedBeanDefinition],
        typeModules: [String: String]
    ) -> String {
        var modules: Set<String> = ["Foundation", "SwiftContext"]
        for bean in beans {
            modules.insert(bean.module)
            let mentioned = bean.targetTypes + bean.dependencies.map(\.type)
            for identifier in mentioned.flatMap(identifiers) {
                if let module = typeModules[identifier] {
                    modules.insert(module)
                }
            }
        }

        return modules.sorted().map { "import \($0)" }.joined(separator: "\n")
    }

    private func definition(bean: ScannedBeanDefinition) -> String {
        let types = bean.targetTypes.map { "\($0).self" }.joined(separator: ", ")

        return "            BeanDefinitionHolder(name: \"\(bean.name)\", definition: BeanDefinition("
            + "beanType: \(bean.concreteType).self, scope: .\(bean.scope), "
            + "targetTypes: [\(types)], instanceSupplier: \(supplier(bean: bean))))"
    }

    private func supplier(bean: ScannedBeanDefinition) -> String {
        guard !bean.dependencies.isEmpty else {
            return "{ _ in \(bean.concreteType)() }"
        }
        let arguments = bean.dependencies.map(resolve).joined(separator: ", ")

        return "{ context in \(bean.concreteType)(\(arguments)) }"
    }

    private func resolve(dependency: DependencyDescriptor) -> String {
        let call = dependency.isCollection
            ? "Array(try context.getBeans(ofType: \(dependency.type).self).values)"
            : "try context.getBean(ofType: \(dependency.type).self)"

        return dependency.label.map { "\($0): \(call)" } ?? call
    }

    /// Все идентификаторы типов в строке типа: `PlistRepository<PreferenceSnapshot>` →
    /// `["PlistRepository", "PreferenceSnapshot"]`. По ним ищем модули для импортов.
    private func identifiers(in type: String) -> [String] {
        var found: [String] = []
        var current = ""
        for character in type {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else {
                if !current.isEmpty { found.append(current) }
                current = ""
            }
        }
        if !current.isEmpty { found.append(current) }

        return found
    }
}
