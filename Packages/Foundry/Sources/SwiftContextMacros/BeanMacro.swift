import SwiftSyntax
import SwiftSyntaxMacros

/// Реализация `@Bean` — маркер метода-фабрики. Ничего не разворачивает: регистрацию по нему генерит
/// `@Configuration` (у него вид на все методы типа сразу). Существует как объявленный peer,
/// чтобы атрибут `@Bean` был легальным в исходнике.
public enum BeanMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
