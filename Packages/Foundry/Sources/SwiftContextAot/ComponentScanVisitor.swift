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
        hierarchy.declare(type: node.name.text, in: module)
        hierarchy.addEdges(from: node.name.text, to: inheritedTypes(of: node.inheritanceClause))

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
        guard let attribute = componentAttribute(in: attributes) else { return }
        let parsed = arguments(of: attribute)
        candidates.append(ComponentCandidate(
            module: module,
            concreteType: name,
            name: parsed.name,
            scope: parsed.scope,
            dependencies: dependencies(of: members)
        ))
    }

    private func componentAttribute(in attributes: AttributeListSyntax) -> AttributeSyntax? {
        for element in attributes {
            guard case .attribute(let attribute) = element,
                  attribute.attributeName.trimmedDescription == "Component" else {
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

    /// Зависимости из собственного init'а. Несколько init'ов — берём с наибольшим числом
    /// параметров (designated с внедрениями); ни одного — пустой список (пустой/наследованный).
    private func dependencies(of members: MemberBlockSyntax) -> [DependencyDescriptor] {
        let inits = members.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
        guard let chosen = inits.max(by: { lhs, rhs in
            lhs.signature.parameterClause.parameters.count
                < rhs.signature.parameterClause.parameters.count
        }) else {
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
