/**
 Базовый КЛАСС сущности — общий словарь тактического DDD. Сущность — доменный объект,
 определяемый ИДЕНТИЧНОСТЬЮ (`id`), а не набором полей: мутабельна, живёт во времени,
 её состояние меняется, но это всё та же сущность. Поэтому равенство и хеш — по `id` (и
 конкретному типу), не по полям (`Hashable` — чтобы класть сущности в `Set`/ключи
 словаря по идентичности).

 В Swift нет `abstract`: класс `open`, напрямую не инстанцируется по соглашению
 (наследуют только конкретные сущности). Один тип — один файл.
 */
open class Entity<ID: Hashable>: Identifiable, Hashable {
    public let id: ID

    public init(id: ID) {
        self.id = id
    }

    /**
     Равенство по идентичности: тот же конкретный тип И тот же `id` (сущности разных
     типов с одинаковым id не равны). Оператор `==` ниже делегирует сюда.
     */
    public func equals(with other: Entity<ID>) -> Bool {
        type(of: self) == type(of: other) && id == other.id
    }

    /// `Equatable` требует статический `==` — он лишь делегирует инстанс-`equals`.
    public static func == (lhs: Entity<ID>, rhs: Entity<ID>) -> Bool {
        lhs.equals(with: rhs)
    }

    /// Хеш по идентичности — согласован с равенством (равные по `id` дают равный хеш).
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
