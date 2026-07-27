/**
 Аналог котлиновского `require(cond) { }` для доменной валидации: бросает доменную
 ошибку, если условие ложно. Применяется в фабриках VO/сущностей на проверке входа
 (нарушение восстановимо — это `throws`, не `precondition`). `@autoclosure` — ошибку
 собираем лениво, только когда правило нарушено. Пример:
 `try require(correct: !value.isEmpty, orThrow: EmptyIdentityValueError())`.
 */
public func require(correct condition: Bool, orThrow error: @autoclosure () -> any DomainError) throws {
    guard condition else {
        throw error()
    }
}
