/**
 Базовый идентификатор сущности — общий словарь тактического DDD. Обёртка над «сырым»
 значением (`Raw`) с равенством и хешем ПО ЗНАЧЕНИЮ и конкретному типу: два id одного
 типа с одинаковым значением — один и тот же id, а id разных типов не равны, даже если
 значение совпало. Конкретные контексты объявляют свой тип наследованием
 (`final class PreferenceId: Identity<String>`), чтобы id одной сущности нельзя было
 подставить вместо id другой (типобезопасность вместо голого `String`/`UUID`).

 Класс (а не `struct`) намеренно — ради наследования конкретных типов id. `open`, но
 напрямую не инстанцируется: работают с конкретными наследниками. `@unchecked Sendable`
 обоснован: `value` иммутабелен (`let`) и сам `Sendable`, общего мутабельного состояния
 нет; `unchecked` лишь потому, что открытый класс не допускает проверяемый conformance.
 */
open class Identity<Raw: Hashable & Sendable>: Hashable, @unchecked Sendable {
    public let value: Raw

    public init(value: Raw) {
        self.value = value
    }

    /**
     Равенство по конкретному типу И значению: `PreferenceId("x")` не равен другому
     `Identity<String>("x")` иного типа. Оператор `==` ниже делегирует сюда.
     */
    public func equals(with other: Identity<Raw>) -> Bool {
        type(of: self) == type(of: other) && value == other.value
    }

    public static func == (lhs: Identity<Raw>, rhs: Identity<Raw>) -> Bool {
        lhs.equals(with: rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}
