import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Точка входа компилятор-плагина: перечисляет макросы, что отдаёт этот модуль.
@main
struct SwiftContextMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ComponentMacro.self,
        ConfigurationMacro.self,
        BeanMacro.self,
    ]
}
