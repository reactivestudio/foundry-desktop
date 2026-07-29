import SwiftParser

/// Скан «класспаса» на `@Component` (точное имя из Spring — `ClassPathBeanDefinitionScanner`, что
/// метод `doScan` отдаёт набором определений бинов). За один проход по ВСЕМ файлам строит граф
/// наследования (`TypeHierarchy`: кто от кого наследуется, какие протоколы — PAT) и собирает
/// кандидатов, затем на каждого считает `targetTypes` = транзитивное замыкание супертипов. Это
/// компиляционная замена рантайм-рефлексии Spring: в Swift нельзя спросить метатип о конформансе
/// без экземпляра, поэтому «наш classloader» — сам исходник.
///
/// После `scan` в `moduleForType` лежит карта «тип → модуль объявления» — генерат по ней
/// импортирует ровно те модули, чьи типы он поминает.
public final class ClassPathBeanDefinitionScanner {
    private let hierarchy = TypeHierarchy()

    public init() {}

    public var moduleForType: [String: String] {
        hierarchy.moduleForType
    }

    public func scan(sources: [(module: String, text: String)]) -> [ScannedBeanDefinition] {
        var candidates: [ComponentCandidate] = []
        for source in sources {
            let visitor = ComponentScanVisitor(module: source.module, hierarchy: hierarchy)
            visitor.walk(Parser.parse(source: source.text))
            candidates.append(contentsOf: visitor.candidates)
        }

        return candidates.map { candidate in
            ScannedBeanDefinition(
                module: candidate.module,
                concreteType: candidate.concreteType,
                name: candidate.name ?? decapitalize(name: candidate.concreteType),
                scope: candidate.scope,
                targetTypes: hierarchy.closure(of: candidate.concreteType),
                dependencies: candidate.dependencies
            )
        }
    }

    private func decapitalize(name: String) -> String {
        guard let first = name.first else { return name }

        return first.lowercased() + name.dropFirst()
    }
}
