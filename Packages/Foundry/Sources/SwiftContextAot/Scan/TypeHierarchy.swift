import Foundation

/// Граф типов всего исходника: объявленные имена (и модуль каждого), PAT-протоколы, рёбра
/// наследования. Накопитель один на весь скан (ссылочный), его пополняет каждый файловый визитор.
/// По нему сканер считает `targetTypes` бина = транзитивное замыкание супертипов и резолвит модуль
/// каждого типа для импортов генерата.
final class TypeHierarchy {
    private var declaredTypes: Set<String> = []
    private var moduleByType: [String: String] = [:]
    private var modulesByType: [String: Set<String>] = [:]
    private var patProtocols: Set<String> = []
    private var edges: [String: [String]] = [:]

    /// Модуль, в котором объявлен тип (по базовому имени, без дженерик-аргументов). Нужен генерату,
    /// чтобы импортировать и КВАЛИФИЦИРОВАТЬ ровно те типы, что он поминает.
    var moduleForType: [String: String] {
        moduleByType
    }

    func declare(type name: String, in module: String) {
        declaredTypes.insert(name)
        if moduleByType[name] == nil {
            moduleByType[name] = module
        }
        modulesByType[name, default: []].insert(module)
    }

    /// ВСЕ модули, объявившие это простое имя. Больше одного — имя неоднозначно: генерат не может
    /// написать ни `Тип.self`, ни `Модуль.Тип.self` без догадки, а имя бина по такому типу столкнётся
    /// с одноимённым. Сканер превращает это в ошибку сборки, если имя реально попадает в генерат.
    func modules(declaring name: String) -> Set<String> {
        modulesByType[name] ?? []
    }

    func markPAT(type name: String) {
        patProtocols.insert(name)
    }

    func addEdges(from subtype: String, to supertypes: [String]) {
        guard !supertypes.isEmpty else { return }
        edges[subtype, default: []].append(contentsOf: supertypes)
    }

    /// Транзитивное замыкание выразимых супертипов. Обходим ВСЕ супертипы (даже нерезолвибельные —
    /// чтобы пройти сквозь них дальше вверх), но в результат берём только выразимые как `T.self`:
    /// объявленные исходнику не-PAT типы, включая конкретные дженерик-инстанциации (все аргументы —
    /// известные типы). Открытые дженерики, PAT-протоколы и внешние типы (Foundation/stdlib) — за
    /// границей системы типов Swift, их в `targetTypes` нет.
    func closure(of concrete: String) -> [String] {
        var ordered = [concrete]
        var seen: Set<String> = [concrete]
        var stack = [concrete]
        while let current = stack.popLast() {
            for supertype in edges[current] ?? [] {
                let base = Self.baseName(of: supertype)
                guard !seen.contains(base) else { continue }
                seen.insert(base)
                if declaredTypes.contains(base) { stack.append(base) }
                if isExpressible(type: supertype) { ordered.append(supertype) }
            }
        }

        return ordered
    }

    private func isExpressible(type raw: String) -> Bool {
        let base = Self.baseName(of: raw)
        guard declaredTypes.contains(base), !patProtocols.contains(base) else { return false }

        // Дженерик-инстанциация выразима как `T.self`, только если ВСЕ её аргументы — известные
        // конкретные типы; иначе это открытый дженерик (аргумент — параметр типа), за границей.
        return Self.genericArguments(of: raw).allSatisfy { declaredTypes.contains(Self.baseName(of: $0)) }
    }

    /// Имя без дженерик-аргументов и пробелов: `Box<Item>` → `Box`.
    static func baseName(of raw: String) -> String {
        let head = raw.split(separator: "<", maxSplits: 1).first.map(String.init) ?? raw

        return head.trimmingCharacters(in: .whitespaces)
    }

    /// Аргументы дженерик-инстанциации верхнего уровня: `Foo<A, B>` → `["A", "B"]`; не-дженерик → `[]`.
    static func genericArguments(of raw: String) -> [String] {
        guard let open = raw.firstIndex(of: "<"), let close = raw.lastIndex(of: ">") else {
            return []
        }
        let inner = raw[raw.index(after: open)..<close]

        return splitTopLevel(arguments: String(inner))
    }

    /// Все идентификаторы типов в строке типа: `Box<Item>` → `["Box", "Item"]`. По ним генерат ищет
    /// модули (для импортов и квалификации), а сканер — неоднозначные имена.
    static func identifiers(in type: String) -> [String] {
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

    /// Разрезать список аргументов по запятым ВЕРХНЕГО уровня (не влезая во вложенные `<...>`).
    private static func splitTopLevel(arguments inner: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for character in inner {
            switch character {
            case "<":
                depth += 1
                current.append(character)
            case ">":
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(character)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { parts.append(last) }

        return parts
    }
}
