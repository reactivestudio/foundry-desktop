import SwiftParser

/// Скан «класспаса» на `@Component` (точное имя из Spring — `ClassPathBeanDefinitionScanner`, что
/// метод `doScan` отдаёт набором определений бинов). За один проход по ВСЕМ файлам строит граф
/// наследования (`TypeHierarchy`: кто от кого наследуется, какие протоколы — PAT) и собирает
/// кандидатов, затем на каждого считает `targetTypes` = транзитивное замыкание супертипов. Это
/// компиляционная замена рантайм-рефлексии Spring: в Swift нельзя спросить метатип о конформансе
/// без экземпляра, поэтому «наш classloader» — сам исходник.
///
/// После `scan` в `moduleForType` лежит карта «тип → модуль объявления» — генерат по ней
/// импортирует и квалифицирует ровно те типы, что поминает; а в `problems` — всё, что выглядит
/// рабочей аннотацией, но бином не станет (скан НЕ МОЛЧИТ, см. [`ScanProblem`]).
public final class ClassPathBeanDefinitionScanner {
    private let hierarchy = TypeHierarchy()

    /// Найденные `@Configuration`-типы (заполняется `scan`). Генерат подмешивает их `definitions()`
    /// в общий `BeanScan`, чтобы источник определений был один. См. [`ScannedConfiguration`].
    public private(set) var configurations: [ScannedConfiguration] = []

    /// Диагностика скана (заполняется `scan`). Не пуста — процессор роняет сборку.
    public private(set) var problems: [ScanProblem] = []

    public init() {}

    public var moduleForType: [String: String] {
        hierarchy.moduleForType
    }

    public func scan(sources: [(module: String, text: String)]) -> [ScannedGenericBeanDefinition] {
        var candidates: [ComponentCandidate] = []
        for source in sources {
            let visitor = ComponentScanVisitor(module: source.module, hierarchy: hierarchy)
            visitor.walk(Parser.parse(source: source.text))
            candidates.append(contentsOf: visitor.candidates)
            configurations.append(contentsOf: visitor.configurations)
            problems.append(contentsOf: visitor.problems)
        }

        let beans = candidates.map { candidate in
            ScannedGenericBeanDefinition(
                module: candidate.module,
                concreteType: candidate.concreteType,
                name: candidate.name ?? decapitalize(name: candidate.concreteType),
                scope: candidate.scope,
                isMainActor: candidate.isMainActor,
                isLazyInit: candidate.isLazyInit,
                isPrimary: candidate.isPrimary,
                targetTypes: hierarchy.closure(of: candidate.concreteType),
                dependencies: candidate.dependencies
            )
        }
        reportDuplicateNames(among: beans)
        reportAmbiguousTypes(among: beans)

        return confineToMainActor(beans: beans)
    }

    /// Разнести конфайнмент главного актора по графу зависимостей до неподвижной точки: бин confined,
    /// если сам `@MainActor` ИЛИ хоть одна его зависимость закрыта confined-бином. Иначе такой бин
    /// остался бы жадным, и `preInstantiateSingletons` полез бы строить `@MainActor`-зависимость на
    /// негарантированном акторе — а это трап `assumeIsolated`, рушащий процесс, вместо ошибки.
    private func confineToMainActor(beans: [ScannedGenericBeanDefinition]) -> [ScannedGenericBeanDefinition] {
        var providersByType: [String: [Int]] = [:]
        for (index, bean) in beans.enumerated() {
            for targetType in bean.targetTypes {
                providersByType[targetType, default: []].append(index)
            }
        }

        var confined = beans.map(\.isMainActor)
        var changed = true
        while changed {
            changed = false
            for (index, bean) in beans.enumerated() where !confined[index] {
                let dependsOnConfined = bean.dependencies.contains { dependency in
                    (providersByType[dependency.type] ?? []).contains { confined[$0] }
                }
                guard dependsOnConfined else { continue }
                confined[index] = true
                changed = true
            }
        }

        return beans.enumerated().map { index, bean in
            confined[index] ? bean.confinedToMainActor() : bean
        }
    }

    /// Имя бина — КЛЮЧ реестра: два бина под одним именем не уживутся. Раньше это всплывало на
    /// старте приложения (`beanDefinitionStore`), теперь — на сборке, с указанием обоих виновников.
    private func reportDuplicateNames(among beans: [ScannedGenericBeanDefinition]) {
        var beansByName: [String: [ScannedGenericBeanDefinition]] = [:]
        for bean in beans {
            beansByName[bean.name, default: []].append(bean)
        }
        for (name, clashing) in beansByName.sorted(by: { $0.key < $1.key }) where clashing.count > 1 {
            let owners = clashing.map { "\($0.module).\($0.concreteType)" }.sorted().joined(separator: ", ")
            problems.append(ScanProblem(
                module: clashing[0].module,
                subject: name,
                reason: "имя бина занято \(clashing.count) типами (\(owners)) — имя это ключ реестра, "
                    + "дай одному явное `name:`"
            ))
        }
    }

    /// Простое имя типа, объявленное в ДВУХ модулях, генерат написать не может: ни `Тип.self` (в
    /// импортах оба модуля — неоднозначность), ни `Модуль.Тип.self` (какой из?). Ругаемся только на
    /// те имена, что реально попадают в генерат, — одноимённые внутренние типы никому не мешают.
    private func reportAmbiguousTypes(among beans: [ScannedGenericBeanDefinition]) {
        for bean in beans {
            let mentioned = [bean.concreteType] + bean.targetTypes + bean.dependencies.map(\.type)
            var seen: Set<String> = []
            for identifier in mentioned.flatMap(TypeHierarchy.identifiers)
                where seen.insert(identifier).inserted {
                let modules = hierarchy.modules(declaring: identifier)
                guard modules.count > 1 else { continue }
                problems.append(ScanProblem(
                    module: bean.module,
                    subject: bean.concreteType,
                    reason: "тип `\(identifier)` объявлен в модулях \(modules.sorted().joined(separator: ", "))"
                        + " — генерату не решить, который имелся в виду; переименуй один"
                ))
            }
        }
    }

    private func decapitalize(name: String) -> String {
        guard let first = name.first else { return name }

        return first.lowercased() + name.dropFirst()
    }
}
