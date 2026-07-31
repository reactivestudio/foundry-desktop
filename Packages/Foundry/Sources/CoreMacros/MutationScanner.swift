import SwiftSyntax

/**
 Ищет в теле метода признак изменения состояния: присваивание (`=`) или составное
 присваивание (`+=`, `-=` и прочие операторы, кончающиеся на `=`, кроме сравнений).
 Обход рекурсивный — мутация в ветке `if`, в цикле или в замыкании тоже считается.

 Обход написан руками, а не наследником `SyntaxVisitor`: prebuilt-бинарь swift-syntax из
 тулчейна не отдаёт наружу приватный символ, на который опирается метатип наследника, и
 плагин не линкуется. Рекурсия по `children` от этого не зависит.

 Нужен ТОЛЬКО для диагностики (см. `InvariantsMacro`), а не для решения «вешать ли
 проверку»: решает CQS-сигнатура. Поэтому сознательно грубо и в сторону перестраховки —
 вызов мутирующего метода (`items.append(...)`) не отличить от чистого без типов, а
 мутация, спрятанная в приватный хелпер, синтаксисом не видна вовсе.
 */
enum MutationScanner {
    private static let comparisons: Set<String> = ["==", "!=", "<=", ">=", "===", "!=="]

    static func finds(mutationIn function: FunctionDeclSyntax) -> Bool {
        guard let body = function.body else {
            return false
        }

        return finds(mutationIn: Syntax(body))
    }

    private static func finds(mutationIn node: Syntax) -> Bool {
        if isMutation(node: node) {
            return true
        }

        return node.children(viewMode: .sourceAccurate).contains { finds(mutationIn: $0) }
    }

    private static func isMutation(node: Syntax) -> Bool {
        if node.is(AssignmentExprSyntax.self) {
            return true
        }
        guard let operation = node.as(BinaryOperatorExprSyntax.self) else {
            return false
        }
        let text = operation.operator.text

        return text.hasSuffix("=") && !comparisons.contains(text)
    }
}
