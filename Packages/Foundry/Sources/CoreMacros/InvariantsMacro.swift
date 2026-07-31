import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/**
 Реализация классовой `@Invariants`: вешает `@Invariant` на команды и инициализаторы корня,
 а на методе, который и возвращает значение, и меняет состояние, выдаёт ошибку CQS. Правила
 отбора и их обоснование — в докблоке самого макроса (`Core/Domain/Entity/Invariants.swift`).
 */
public struct InvariantsMacro: MemberAttributeMacro {
    /// Не команда, хотя ничего не возвращает: рекурсия проверки и служебный `Hashable`.
    private static let reserved: Set<String> = ["checkInvariants", "hash"]

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        let checks = checkNames(of: node, in: declaration)
        let invariant = invariant(from: node, of: declaration)

        if let initializer = member.as(InitializerDeclSyntax.self) {
            return isMarked(attributes: initializer.attributes) ? [] : [invariant]
        }

        guard let function = member.as(FunctionDeclSyntax.self),
            !isMarked(attributes: function.attributes)
        else {
            return []
        }

        guard isCommand(function: function, besides: checks) else {
            diagnose(hiddenCommand: function, besides: checks, in: context)

            return []
        }

        return [invariant]
    }

    /**
     Имена методов, которые сами проверяют инварианты, — их аннотировать нельзя, иначе
     проверка вызовет себя. Кроме общего `checkInvariants` сюда попадает метод с классовой
     аннотации и методы, названные в `@Invariant(check:)` на отдельных командах.
     */
    private static func checkNames(
        of node: AttributeSyntax,
        in declaration: some DeclGroupSyntax
    ) -> Set<String> {
        var names = reserved
        if let literal = argument(of: node)?.as(StringLiteralExprSyntax.self) {
            names.insert(literal.segments.description)
        }
        for member in declaration.memberBlock.members {
            guard let attributes = member.decl.asProtocol(WithAttributesSyntax.self)?.attributes else {
                continue
            }
            for case .attribute(let attribute) in attributes {
                guard attribute.trimmedDescription.hasPrefix("@Invariant"),
                    let reference = argument(of: attribute)?.trimmedDescription,
                    let name = reference.split(separator: ".").last
                else {
                    continue
                }
                names.insert(String(name))
            }
        }

        return names
    }

    /**
     Имя метода проверки с классовой аннотации превращаем в типизированную ссылку `Тип.метод`
     и ставим её каждой команде: снаружи класса такую ссылку не написать (цикл раскрытия
     макроса), а внутри — можно, и компилятор её проверит.
     */
    private static func invariant(
        from node: AttributeSyntax,
        of declaration: some DeclGroupSyntax
    ) -> AttributeSyntax {
        guard let literal = argument(of: node)?.as(StringLiteralExprSyntax.self),
            let type = declaration.asProtocol(NamedDeclSyntax.self)?.name.text
        else {
            return "@Invariant"
        }

        return "@Invariant(check: \(raw: type).\(raw: literal.segments.description))"
    }

    private static func argument(of node: AttributeSyntax) -> ExprSyntax? {
        guard case .argumentList(let arguments) = node.arguments else {
            return nil
        }

        return arguments.first?.expression
    }

    /// Проставленную руками аннотацию не дублируем — ручная форма старше классовой.
    private static func isMarked(attributes: AttributeListSyntax) -> Bool {
        attributes.contains { $0.trimmedDescription.hasPrefix("@Invariant") }
    }

    private static func isCommand(function: FunctionDeclSyntax, besides checks: Set<String>) -> Bool {
        let modifiers = Set(function.modifiers.map(\.name.text))
        let isHidden = !modifiers.isDisjoint(with: ["private", "fileprivate"])
        let isTypeLevel = !modifiers.isDisjoint(with: ["static", "class"])
        let isCheck = checks.contains(function.name.text)

        return !isHidden && !isTypeLevel && !isCheck && function.signature.returnClause == nil
    }

    /**
     Метод вернул значение (значит, объявил себя запросом), но присваивает состоянию —
     молча оставить его без проверки нельзя, это была бы ровно та дыра, ради закрытия
     которой классовую форму и заводят. Приватные не трогаем: они и есть внутренности команды.
     */
    private static func diagnose(
        hiddenCommand function: FunctionDeclSyntax,
        besides checks: Set<String>,
        in context: some MacroExpansionContext
    ) {
        let modifiers = Set(function.modifiers.map(\.name.text))
        guard modifiers.isDisjoint(with: ["private", "fileprivate", "static", "class"]),
            !checks.contains(function.name.text),
            MutationScanner.finds(mutationIn: function)
        else {
            return
        }

        context.diagnose(
            Diagnostic(node: Syntax(function.name), message: CommandContractDiagnostic.mixedCommandAndQuery)
        )
    }
}
