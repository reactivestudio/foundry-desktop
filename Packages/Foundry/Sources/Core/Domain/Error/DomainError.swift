/**
 Базовая роль ошибок доменного слоя — общий словарь (интерфейс + реализации, аналог
 котлиновского `sealed class DomainError(val message)`). Протокол, а конкретные ошибки —
 `struct`: под Swift 6 (строгая concurrency) `Error`-классу пришлось бы вешать
 `@unchecked Sendable` на каждый подкласс; value-тип получает `Sendable` бесплатно.
 Каждая ошибка несёт СВОЙ контекст полями и собирает `message` сама (плейсхолдеры
 подставляет в интерполяции), без `switch`.

 - `message` — человекочитаемый текст для логов;
 - `context` — структурный контекст (те же поля строками) для структурного лога/рендера;
   по умолчанию пусто, ошибка с контекстом переопределяет.

 Деление по слоям: `DomainError` — нарушения доменных правил; `ApplicationError`/
 `InfrastructureError` появятся со своими слоями. В Swift нет отдельных «исключений» —
 `throw` бросает любой `Error`.
 */
public protocol DomainError: Error, CustomStringConvertible {
    var message: String { get }
    var context: [String: String] { get }
}

public extension DomainError {
    var description: String {
        message
    }

    var context: [String: String] {
        [:]
    }
}
