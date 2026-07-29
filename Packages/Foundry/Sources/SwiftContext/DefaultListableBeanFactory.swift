/**
 `DefaultListableBeanFactory` — рабочий тип фабрики бинов: реализует `BeanFactory`,
 `ListableBeanFactory`, `BeanDefinitionRegistry` и `SingletonBeanRegistry` в одном типе (в Spring
 это ровно один класс на все эти интерфейсы). Три таблицы: `definitions` (имя → рецепт), `byType`
 (тип → имена, индекс из `targetTypes`) и `singletons` (имя → готовый объект). Резолв по типу =
 найти имена в `byType`, выбрать кандидата, дальше по имени. Изоляция — от использования на одном
 акторе (`ApplicationContext` собирается на `@MainActor`); внутреннего замка нет.
 */
public final class DefaultListableBeanFactory {
    private var definitions: [String: BeanDefinition] = [:]
    private var definitionNames: [String] = []
    private var byType: [ObjectIdentifier: [String]] = [:]
    private var singletons: [String: Any] = [:]
    private var singletonNames: [String] = []
    private var aliasToName: [String: String] = [:]
    private var inCreation: Set<String> = []

    public init() {}

    /// Жадная преинстанциация не-ленивых синглтонов (дефолт Spring, `preInstantiateSingletons`):
    /// собрать граф на старте и упасть сразу при кривой проводке, а не лениво при первом резолве.
    public func preInstantiateSingletons() throws {
        for name in definitionNames {
            guard let definition = definitions[name], definition.scope == .singleton,
                  !definition.isLazyInit else {
                continue
            }
            _ = try getBean(name: name)
        }
    }

    // MARK: - Приватная кухня

    private func canonicalName(of name: String) -> String {
        aliasToName[name] ?? name
    }

    private func index(name: String, type: Any.Type) {
        let key = ObjectIdentifier(type)
        if byType[key]?.contains(name) != true {
            byType[key, default: []].append(name)
        }
    }

    private func cacheSingleton(name: String, object: Any) {
        if singletons[name] == nil {
            singletonNames.append(name)
        }
        singletons[name] = object
    }

    private func scope(of name: String) throws -> BeanScope {
        let canonical = canonicalName(of: name)
        if let definition = definitions[canonical] {
            return definition.scope
        }
        if singletons[canonical] != nil {
            return .singleton
        }
        throw BeansException.noSuchBeanDefinitionNamed(canonical)
    }

    private func createBean(name: String, definition: BeanDefinition) throws -> Any {
        guard inCreation.insert(name).inserted else {
            throw BeansException.beanCurrentlyInCreation(name: name)
        }
        defer { inCreation.remove(name) }

        let object: Any
        do {
            object = try definition.instanceSupplier(self)
        } catch let error as BeansException {
            throw error
        } catch {
            throw BeansException.beanCreation(name: name, cause: error)
        }

        if definition.scope == .singleton {
            cacheSingleton(name: name, object: object)
        }

        return object
    }

    private func uniqueName<T>(among names: [String], forType requiredType: T.Type) throws -> String {
        switch names.count {
        case 0:
            throw BeansException.noSuchBeanDefinition(requiredType)
        case 1:
            return names[0]
        default:
            let primary = names.filter { definitions[$0]?.isPrimary == true }
            guard primary.count == 1 else {
                throw BeansException.noUniqueBeanDefinition(requiredType, candidates: names)
            }
            return primary[0]
        }
    }
}

// MARK: - BeanFactory

extension DefaultListableBeanFactory: BeanFactory {
    public func getBean(name: String) throws -> Any {
        let canonical = canonicalName(of: name)
        if let singleton = singletons[canonical] {
            return singleton
        }
        guard let definition = definitions[canonical] else {
            throw BeansException.noSuchBeanDefinitionNamed(canonical)
        }

        return try createBean(name: canonical, definition: definition)
    }

    public func getBean<T>(name: String, ofType requiredType: T.Type) throws -> T {
        let bean = try getBean(name: name)
        guard let typed = bean as? T else {
            throw BeansException.beanNotOfRequiredType(
                name: name, required: requiredType, actual: type(of: bean)
            )
        }

        return typed
    }

    public func getBean<T>(ofType requiredType: T.Type) throws -> T {
        let name = try uniqueName(among: getBeanNames(forType: requiredType), forType: requiredType)

        return try getBean(name: name, ofType: requiredType)
    }

    public func containsBean(name: String) -> Bool {
        let canonical = canonicalName(of: name)

        return definitions[canonical] != nil || singletons[canonical] != nil
    }

    public func isSingleton(name: String) throws -> Bool {
        try scope(of: name) == .singleton
    }

    public func isPrototype(name: String) throws -> Bool {
        try scope(of: name) == .prototype
    }

    public func getType(name: String) throws -> Any.Type {
        let canonical = canonicalName(of: name)
        if let definition = definitions[canonical] {
            return definition.beanType
        }
        if let singleton = singletons[canonical] {
            return type(of: singleton)
        }
        throw BeansException.noSuchBeanDefinitionNamed(canonical)
    }

    public func getAliases(name: String) -> [String] {
        let canonical = canonicalName(of: name)

        return aliasToName.filter { $0.value == canonical }.map(\.key)
    }
}

// MARK: - ListableBeanFactory

extension DefaultListableBeanFactory: ListableBeanFactory {
    public func getBeanNames(forType type: Any.Type) -> [String] {
        byType[ObjectIdentifier(type)] ?? []
    }

    public func getBeans<T>(ofType type: T.Type) throws -> [String: T] {
        var beans: [String: T] = [:]
        for name in getBeanNames(forType: type) {
            if let bean = try getBean(name: name) as? T {
                beans[name] = bean
            }
        }

        return beans
    }
}

// MARK: - SingletonBeanRegistry

extension DefaultListableBeanFactory: SingletonBeanRegistry {
    public func registerSingleton(name: String, singletonObject: Any) {
        cacheSingleton(name: name, object: singletonObject)
        index(name: name, type: type(of: singletonObject))
    }

    public func getSingleton(name: String) -> Any? {
        singletons[canonicalName(of: name)]
    }

    public func containsSingleton(name: String) -> Bool {
        singletons[canonicalName(of: name)] != nil
    }

    public func getSingletonNames() -> [String] {
        singletonNames
    }

    public var singletonCount: Int {
        singletonNames.count
    }
}

// MARK: - BeanDefinitionRegistry / AliasRegistry

extension DefaultListableBeanFactory: BeanDefinitionRegistry {
    public func registerBeanDefinition(name: String, beanDefinition: BeanDefinition) throws {
        guard definitions[name] == nil else {
            throw BeansException.beanDefinitionStore(
                name: name, reason: "определение с этим именем уже зарегистрировано"
            )
        }
        definitions[name] = beanDefinition
        definitionNames.append(name)
        for targetType in beanDefinition.targetTypes {
            index(name: name, type: targetType)
        }
    }

    public func removeBeanDefinition(name: String) throws {
        guard definitions.removeValue(forKey: name) != nil else {
            throw BeansException.noSuchBeanDefinitionNamed(name)
        }
        definitionNames.removeAll { $0 == name }
        for key in byType.keys {
            byType[key]?.removeAll { $0 == name }
        }
    }

    public func getBeanDefinition(name: String) throws -> BeanDefinition {
        guard let definition = definitions[name] else {
            throw BeansException.noSuchBeanDefinitionNamed(name)
        }

        return definition
    }

    public func containsBeanDefinition(name: String) -> Bool {
        definitions[canonicalName(of: name)] != nil
    }

    public func getBeanDefinitionNames() -> [String] {
        definitionNames
    }

    public var beanDefinitionCount: Int {
        definitionNames.count
    }

    public func isBeanNameInUse(name: String) -> Bool {
        definitions[name] != nil || aliasToName[name] != nil || singletons[name] != nil
    }
}

extension DefaultListableBeanFactory: AliasRegistry {
    public func registerAlias(name: String, alias: String) {
        aliasToName[alias] = name
    }

    public func removeAlias(alias: String) {
        aliasToName[alias] = nil
    }

    public func isAlias(name: String) -> Bool {
        aliasToName[name] != nil
    }
}
