import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Точка входа compiler-плагина: список макросов, которые он предоставляет компилятору.
@main
struct CoreMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [InvariantsMacro.self, InvariantMacro.self]
}
