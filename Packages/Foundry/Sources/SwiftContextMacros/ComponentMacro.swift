import SwiftSyntax
import SwiftSyntaxMacros

/// Реализация `@Component` — маркер типа-бина. Ничего не разворачивает: определение бина по нему
/// генерит `BeanScan` (у скан-плагина вид на весь исходник сразу — цепочки наследования, все
/// реализации контракта). Существует как объявленный peer, чтобы атрибут `@Component` был легальным
/// в исходнике — ровно как `@Bean`.
public enum ComponentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
