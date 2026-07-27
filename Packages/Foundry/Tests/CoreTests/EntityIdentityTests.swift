@testable import Core
import Testing

private final class FooId: Identity<String>, @unchecked Sendable {}
private final class BarId: Identity<String>, @unchecked Sendable {}

private final class FooEntity: Entity<FooId> {}
private final class OtherFooEntity: Entity<FooId> {}

@Suite("Тождество сущностей и идентичностей")
struct EntityIdentityTests {

    @Test("Идентичность равна по значению")
    func identityEqualsByValue() {
        #expect(FooId(value: "x") == FooId(value: "x"))
        #expect(FooId(value: "x") != FooId(value: "y"))
    }

    @Test("Идентичности разных типов не равны при одном значении")
    func identityDiffersByType() {
        let foo: Identity<String> = FooId(value: "x")
        let bar: Identity<String> = BarId(value: "x")
        #expect(foo != bar)
    }

    @Test("Идентичности с равным значением дают равный хеш")
    func identityHashMatchesEquality() {
        #expect(FooId(value: "x").hashValue == FooId(value: "x").hashValue)
    }

    @Test("Сущность равна по id")
    func entityEqualsById() {
        let id = FooId(value: "1")
        #expect(FooEntity(id: id) == FooEntity(id: id))
        #expect(FooEntity(id: FooId(value: "1")) != FooEntity(id: FooId(value: "2")))
    }

    @Test("Сущности разных типов с одним id не равны")
    func entityDiffersByType() {
        let id = FooId(value: "1")
        let foo: Entity<FooId> = FooEntity(id: id)
        let other: Entity<FooId> = OtherFooEntity(id: id)
        #expect(foo != other)
    }
}
