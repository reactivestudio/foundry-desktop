import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/**
 Реализация `@Invariant`: дописывает в начало тела `defer { checkInvariants() }`.
 `defer` первым стейтментом — чтобы проверка сработала на ЛЮБОМ выходе (обычном, раннем
 `return`, выбросе), но уже после всех изменений команды.
 */
public struct InvariantMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        let statements = declaration.body?.statements ?? []
        let guardStatement: CodeBlockItemSyntax = "defer { \(raw: checkName(of: node))() }"

        return [guardStatement] + Array(statements)
    }

    /**
     Имя метода проверки. По умолчанию `checkInvariants`; при явном
     `@Invariant(check: Preference.checkNaming)` берём последний компонент ссылки на метод —
     тип в подставляемом вызове не нужен, вызов идёт на `self`.
     */
    private static func checkName(of node: AttributeSyntax) -> String {
        guard case .argumentList(let arguments) = node.arguments,
            let reference = arguments.first?.expression.trimmedDescription,
            let name = reference.split(separator: ".").last
        else {
            return "checkInvariants"
        }

        return String(name)
    }
}
