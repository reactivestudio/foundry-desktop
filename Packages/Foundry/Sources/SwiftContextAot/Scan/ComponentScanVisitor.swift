import Foundation
import SwiftSyntax

/// Файловый визитор скана: за один проход по дереву одного исходника пополняет общий `TypeHierarchy`
/// (объявленные типы с их модулем, PAT-протоколы, рёбра наследования) и собирает кандидатов
/// `@Component` этого файла. Скоуп/имя берёт из атрибута, зависимости — из выбранного init'а.
/// Портов у `@Component` нет: цепочку супертипов строит сам граф, скану ручных подсказок не нужно.
final class ComponentScanVisitor: SyntaxVisitor {
    let module: String
    let hierarchy: TypeHierarchy
    private(set) var candidates: [ComponentCandidate] = []
    private(set) var configurations: [ScannedConfiguration] = []
    private(set) var problems: [ScanProblem] = []

    init(module: String, hierarchy: TypeHierarchy) {
        self.module = module
        self.hierarchy = hierarchy
        super.init(viewMode: .sourceAccurate)
    }

    // Метка `_` тут обязана быть: это оверрайды `SyntaxVisitor.visit(_:)` из SwiftSyntax —
    // сменишь метку, и это уже не оверрайд (тот же случай, что updateNSView(_:) в правиле).
    // swiftlint:disable no_underscore_argument_label
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        hierarchy.declare(type: name, in: module)
        hierarchy.addEdges(from: name, to: inheritedTypes(of: node.inheritanceClause))
        if hasAssociatedType(in: node.memberBlock) {
            hierarchy.markPAT(type: name)
        }

        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, inheritance: node.inheritanceClause,
               attributes: node.attributes, members: node.memberBlock)

        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, inheritance: node.inheritanceClause,
               attributes: node.attributes, members: node.memberBlock)

        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, inheritance: node.inheritanceClause,
               attributes: node.attributes, members: node.memberBlock)

        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        hierarchy.declare(type: name, in: module)
        hierarchy.addEdges(from: name, to: inheritedTypes(of: node.inheritanceClause))
        // `enum` бином быть не может: контейнеру нечего позвать (конструктора нет), а
        // `@Configuration` вдобавок требует инстанса — генерат зовёт `Тип().definitions()`.
        // Раньше такая аннотация молча выпадала из скана, и бины просто не появлялись.
        if let stereotype = stereotypeAttribute(in: node.attributes) {
            report(type: name, reason: "`@\(stereotype.attributeName.trimmedDescription)` на `enum` — "
                + "бином не станет (конструктора нет). Сделай `struct`/`final class` "
                + "или заведи бин `@Bean`-методом в `@Configuration`")
        }
        if attribute(named: "Configuration", in: node.attributes) != nil {
            report(type: name, reason: "`@Configuration` на `enum` — генерат зовёт `\(name)().definitions()`, "
                + "инстанса у `enum` нет. Сделай `struct` с `init()`")
        }

        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let base = TypeHierarchy.baseName(of: node.extendedType.trimmedDescription)
        hierarchy.addEdges(from: base, to: inheritedTypes(of: node.inheritanceClause))

        return .visitChildren
    }
    // swiftlint:enable no_underscore_argument_label

    private func record(
        name: String,
        inheritance: InheritanceClauseSyntax?,
        attributes: AttributeListSyntax,
        members: MemberBlockSyntax
    ) {
        hierarchy.declare(type: name, in: module)
        hierarchy.addEdges(from: name, to: inheritedTypes(of: inheritance))
        // `@Configuration` в Spring — тоже `@Component`: скан подхватывает его наравне, а `@Bean`-методы
        // становятся бинами. Собираем конфиги отдельным списком (сам конфиг бином не регистрируем —
        // нужны только его `definitions()`), генерат подмешает их в общий `BeanScan`.
        if attribute(named: "Configuration", in: attributes) != nil {
            configurations.append(ScannedConfiguration(module: module, concreteType: name))
        }
        guard let stereotype = stereotypeAttribute(in: attributes) else { return }
        let parsed = arguments(of: stereotype)
        candidates.append(ComponentCandidate(
            module: module,
            concreteType: name,
            name: parsed.name,
            scope: parsed.scope,
            isMainActor: attribute(named: "MainActor", in: attributes) != nil,
            // `@Primary`/`@Lazy` — подлинные аннотации Spring; без них одноимённые поля
            // `BeanDefinition` были недостижимы из скана (фабрика их читает, а выставить нечем).
            isLazyInit: attribute(named: "Lazy", in: attributes) != nil,
            isPrimary: attribute(named: "Primary", in: attributes) != nil,
            dependencies: dependencies(of: members, type: name)
        ))
    }

    private func report(type: String, reason: String) {
        problems.append(ScanProblem(module: module, subject: type, reason: reason))
    }

    /// Первый присутствующий стереотип-бин: `@Component` или его специализации по слоям
    /// (`@DomainService`, `@ApplicationService`, `@UseCase`, `@Repository`, `@Store`). В Spring
    /// специализации мета-аннотированы `@Component`; в Swift мета-аннотаций нет, поэтому скан знает
    /// их имена и трактует одинаково — как кандидата в бины. Различие стереотипов — для читателя
    /// (слой и роль), контейнеру они равны.
    private func stereotypeAttribute(in attributes: AttributeListSyntax) -> AttributeSyntax? {
        for name in [
            "Component", "DomainService", "ApplicationService", "UseCase", "Repository", "Store",
        ] {
            if let found = attribute(named: name, in: attributes) {
                return found
            }
        }

        return nil
    }

    private func attribute(named target: String, in attributes: AttributeListSyntax) -> AttributeSyntax? {
        for element in attributes {
            guard case .attribute(let attribute) = element,
                  attribute.attributeName.trimmedDescription == target else {
                continue
            }

            return attribute
        }

        return nil
    }

    private func arguments(of attribute: AttributeSyntax) -> (name: String?, scope: String) {
        guard case .argumentList(let list) = attribute.arguments else {
            return (nil, "singleton")
        }
        var name: String?
        var scope = "singleton"
        for argument in list {
            switch argument.label?.text {
            case "scope":
                if argument.expression.trimmedDescription.contains("prototype") {
                    scope = "prototype"
                }
            case "name":
                name = stringLiteral(of: argument.expression)
            default:
                continue
            }
        }

        return (name, scope)
    }

    /// Зависимости из конструктора внедрения. Ни одного init'а — пустой список
    /// (пустой/наследованный конструктор).
    private func dependencies(of members: MemberBlockSyntax, type: String) -> [DependencyDescriptor] {
        let inits = members.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
        guard let chosen = injectionInit(among: inits, type: type) else {
            return []
        }

        return chosen.signature.parameterClause.parameters.map { parameter in
            let label = parameter.firstName.text == "_" ? nil : parameter.firstName.text
            var type = parameter.type.trimmedDescription
            var isCollection = false
            if type.hasPrefix("["), type.hasSuffix("]"), !type.contains(":") {
                isCollection = true
                type = String(type.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            }

            return DependencyDescriptor(label: label, type: type, isCollection: isCollection)
        }
    }

    /// Конструктор внедрения: один init — он и есть (как в Spring: единственный конструктор
    /// внедряется без аннотации). Несколько — нужен ровно один `@Autowired`, иначе ОШИБКА, а не
    /// догадка: прежняя эвристика «у кого больше параметров» молча выбирала, например, тестовый
    /// `init(title:subtitle:count:)` вместо `init(runner:)` и валила старт на `noSuchBeanDefinition`.
    private func injectionInit(
        among inits: [InitializerDeclSyntax],
        type: String
    ) -> InitializerDeclSyntax? {
        guard inits.count > 1 else {
            return inits.first
        }
        let marked = inits.filter { attribute(named: "Autowired", in: $0.attributes) != nil }
        switch marked.count {
        case 1:
            return marked[0]
        case 0:
            report(type: type, reason: "init'ов \(inits.count), ни один не помечен `@Autowired` — "
                + "непонятно, каким внедрять. Помечь конструктор внедрения")
        default:
            report(type: type, reason: "`@Autowired` стоит на \(marked.count) init'ах — оставь один")
        }

        return nil
    }

    private func inheritedTypes(of clause: InheritanceClauseSyntax?) -> [String] {
        clause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
    }

    private func hasAssociatedType(in members: MemberBlockSyntax) -> Bool {
        members.members.contains { $0.decl.is(AssociatedTypeDeclSyntax.self) }
    }

    private func stringLiteral(of expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return nil }

        return literal.segments
            .compactMap { $0.as(StringSegmentSyntax.self)?.content.text }
            .joined()
    }
}
