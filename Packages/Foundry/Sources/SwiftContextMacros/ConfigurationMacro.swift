import SwiftSyntax
import SwiftSyntaxMacros

/**
 Реализация `@Configuration`. Extension-макрос: читает методы типа, помеченные `@Bean`, и генерит
 `definitions() -> [BeanDefinitionHolder]` — те же `@Bean` как ДАННЫЕ для контекста: имя (явное из
 `@Bean(name: "…")` или имя метода), `targetTypes: [R]`, `instanceSupplier` зовёт сам метод, резолвя
 параметры из контейнера по типу (как аргументы `@Bean` в Spring). Параметры метода —
 зависимости-бины. Скоуп — синглтон (дефолтный `@Bean` Spring). Всё локально: у макроса вид на все
 методы типа, скан не нужен (в отличие от `@Component`).
 */
public enum ConfigurationMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let definitions = declaration.memberBlock.members
            .compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter(isBean)
            .compactMap(definition)
            .joined(separator: ",\n")
        let prefix = declaration.extensionMemberAccessPrefix

        let generated: DeclSyntax = """
        extension \(raw: type.trimmedDescription) {
            \(raw: prefix)func definitions() -> [BeanDefinitionHolder] {
                [
        \(raw: definitions)
                ]
            }
        }
        """

        guard let ext = generated.as(ExtensionDeclSyntax.self) else {
            return []
        }

        return [ext]
    }

    private static func isBean(method: FunctionDeclSyntax) -> Bool {
        beanAttribute(of: method) != nil
    }

    private static func beanAttribute(of method: FunctionDeclSyntax) -> AttributeSyntax? {
        for element in method.attributes {
            guard case .attribute(let attribute) = element,
                  attribute.attributeName.trimmedDescription == "Bean" else {
                continue
            }

            return attribute
        }

        return nil
    }

    /// Имя бина: явное `@Bean(name: "…")` или имя метода (как в Spring).
    private static func beanName(of method: FunctionDeclSyntax) -> String {
        guard let attribute = beanAttribute(of: method),
              case .argumentList(let list) = attribute.arguments,
              let first = list.first,
              let literal = first.expression.as(StringLiteralExprSyntax.self) else {
            return method.name.text
        }

        return literal.segments
            .compactMap { $0.as(StringSegmentSyntax.self)?.content.text }
            .joined()
    }

    /// `@Bean func x(p: P) -> R` → `BeanDefinitionHolder` с supplier'ом, который зовёт
    /// метод, резолвя параметры из контейнера по ТИПУ (как аргументы `@Bean` в Spring).
    private static func definition(from method: FunctionDeclSyntax) -> String? {
        guard let returnType = method.signature.returnClause?.type.trimmedDescription else {
            return nil
        }

        let name = beanName(of: method)
        let parameters = method.signature.parameterClause.parameters
        let arguments = parameters.map { parameter -> String in
            let type = parameter.type.trimmedDescription
            let label = parameter.firstName.text
            let resolve = "try context.getBean(ofType: \(type).self)"

            return label == "_" ? resolve : "\(label): \(resolve)"
        }
        let call = parameters.isEmpty
            ? "{ _ in self.\(method.name.text)() }"
            : "{ context in self.\(method.name.text)(\(arguments.joined(separator: ", "))) }"

        return "            BeanDefinitionHolder(name: \"\(name)\", definition: BeanDefinition("
            + "beanType: \(returnType).self, targetTypes: [\(returnType).self], "
            + "instanceSupplier: \(call)))"
    }
}
