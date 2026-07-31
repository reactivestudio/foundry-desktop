@testable import Core
import Testing

/**
 Корень для проверки самой аннотации: считает, сколько раз его инварианты проверили.
 Часть команд помечена `@Invariant`, часть намеренно нет — аннотация опциональна.
 */
private final class Basket: AggregateRoot<String> {
    private(set) var items: [String] = []
    private(set) var checks = 0
    private(set) var namings = 0
    private let limit: Int

    @Invariant
    init(limit: Int) {
        self.limit = limit
        super.init(id: "basket")
    }

    @Invariant
    func add(item: String) {
        items.append(item)
    }

    @Invariant
    func addTwice(item: String) {
        items.append(item)
        items.append(item)
    }

    @Invariant
    func drop(item: String) {
        guard items.contains(item) else {
            return
        }
        items = items.filter { $0 != item }
    }

    @Invariant
    func rename(item: String, to name: String) throws {
        guard !name.isEmpty else {
            throw Failure.emptyName
        }
        items = items.map { $0 == item ? name : $0 }
    }

    /// Команда без аннотации — проверки не будет: это и есть опциональность.
    func addUnchecked(item: String) {
        items.append(item)
    }

    /// Своя проверка вместо общей — форма `@Invariant(check:)`.
    @Invariant(check: Basket.checkNaming)
    func label(item: String) {
        items.append(item)
    }

    func contains(item: String) -> Bool {
        items.contains(item)
    }

    func checkNaming() {
        namings += 1
        check(correct: items.allSatisfy { !$0.isEmpty }, orFail: "позиция без имени")
    }

    override func checkInvariants() {
        checks += 1
        check(correct: items.count <= limit, orFail: "в корзине больше позиций, чем разрешено")
    }

    enum Failure: Error {
        case emptyName
    }
}

/**
 Корень с классовой аннотацией: ни одной пометки на командах — их обязана расставить
 `@Invariants`. Одна команда перебита своей `@Invariant(check:)`.
 */
@Invariants
private final class Shelf: AggregateRoot<String> {
    private(set) var items: [String] = []
    private(set) var checks = 0
    private(set) var namings = 0

    init() {
        super.init(id: "shelf")
    }

    func add(item: String) {
        items.append(item)
    }

    @Invariant(check: Shelf.checkNaming)
    func label(item: String) {
        items.append(item)
    }

    func contains(item: String) -> Bool {
        items.contains(item)
    }

    func checkNaming() {
        namings += 1
    }

    override func checkInvariants() {
        checks += 1
        check(correct: items.count <= 2, orFail: "на полке больше позиций, чем разрешено")
    }
}

/// Корень, которому классовая аннотация задала НЕ общий метод проверки.
@Invariants(check: "checkNaming")
private final class Rack: AggregateRoot<String> {
    private(set) var items: [String] = []
    private(set) var namings = 0

    init() {
        super.init(id: "rack")
    }

    func add(item: String) {
        items.append(item)
    }

    func checkNaming() {
        namings += 1
        check(correct: items.allSatisfy { !$0.isEmpty }, orFail: "позиция без имени")
    }
}

@Suite("Аннотации @Invariants/@Invariant: проверка инвариантов агрегата")
struct AggregateInvariantTests {

    @Test("Помеченный инициализатор проверяет инварианты — агрегат не рождается невалидным")
    func initializerChecks() {
        #expect(Basket(limit: 2).checks == 1)
    }

    @Test("Помеченная команда проверяет инварианты на выходе")
    func commandChecks() {
        let basket = Basket(limit: 2)
        basket.add(item: "болт")
        #expect(basket.checks == 2)
        #expect(basket.items == ["болт"])
    }

    @Test("Проверка одна на команду, а не на каждое изменение внутри неё")
    func checksOncePerCommand() {
        let basket = Basket(limit: 2)
        basket.addTwice(item: "болт")
        #expect(basket.checks == 2)
    }

    @Test("Ранний return из команды проверку не обходит")
    func earlyReturnChecks() {
        let basket = Basket(limit: 2)
        basket.drop(item: "гайка")
        #expect(basket.checks == 2)
    }

    @Test("Бросившая команда проверку тоже проходит — полусостояние ловится")
    func throwingCommandChecks() {
        let basket = Basket(limit: 2)
        #expect(throws: Basket.Failure.self) {
            try basket.rename(item: "болт", to: "")
        }
        #expect(basket.checks == 2)
    }

    @Test("Непомеченная команда инварианты не проверяет — аннотация опциональна")
    func uncheckedCommandSkipsInvariants() {
        let basket = Basket(limit: 2)
        basket.addUnchecked(item: "болт")
        #expect(basket.checks == 1)
        #expect(basket.items == ["болт"])
    }

    @Test("Запрос инварианты не трогает")
    func queryDoesNotCheck() {
        let basket = Basket(limit: 2)
        _ = basket.contains(item: "болт")
        #expect(basket.checks == 1)
    }

    @Test("Переданный метод проверки зовётся вместо общего")
    func explicitCheckReplacesDefault() {
        let basket = Basket(limit: 2)
        basket.label(item: "болт")
        #expect(basket.namings == 1)
        #expect(basket.checks == 1)
    }

    @Test("Классовая аннотация проверяет команды и инициализатор, пометок на них нет")
    func classWideChecks() {
        let shelf = Shelf()
        #expect(shelf.checks == 1)
        shelf.add(item: "болт")
        #expect(shelf.checks == 2)
    }

    @Test("Классовая аннотация не трогает запросы")
    func classWideSkipsQueries() {
        let shelf = Shelf()
        _ = shelf.contains(item: "болт")
        #expect(shelf.checks == 1)
    }

    @Test("Своя аннотация на команде старше классовой")
    func methodAnnotationWinsOverClass() {
        let shelf = Shelf()
        shelf.label(item: "болт")
        #expect(shelf.namings == 1)
        #expect(shelf.checks == 1)
    }

    @Test("Метод проверки с классовой аннотации попадает на все её команды")
    func classWideCheckMethod() {
        let rack = Rack()
        rack.add(item: "болт")
        #expect(rack.namings == 2)
    }

    @Test("Нарушенный инвариант роняет процесс — это баг кода, а не ошибка данных")
    func brokenInvariantTraps() async {
        await #expect(processExitsWith: .failure) {
            let basket = Basket(limit: 1)
            basket.addTwice(item: "болт")
        }
    }

    @Test("Нарушение переданной проверки роняет процесс так же")
    func brokenExplicitCheckTraps() async {
        await #expect(processExitsWith: .failure) {
            let basket = Basket(limit: 5)
            basket.label(item: "")
        }
    }
}
