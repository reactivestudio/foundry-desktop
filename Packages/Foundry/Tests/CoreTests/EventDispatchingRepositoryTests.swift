@testable import Core
import Testing

private final class ThingId: Identity<String>, @unchecked Sendable {}

private struct HappenedEvent: DomainEvent {
    let tag: String
}

private final class Thing: DispatchingAggregateRoot<ThingId> {}

/// In-memory-репозиторий-двойник; считает вызовы `save`, чтобы проверить делегирование.
private final class InMemoryThingRepository: Repository {
    private var storage: [ThingId: Thing] = [:]
    private(set) var saveCount = 0

    func find(id: ThingId) -> Thing? {
        storage[id]
    }

    @discardableResult
    func save(entity: Thing) -> Thing {
        saveCount += 1
        storage[entity.id] = entity

        return entity
    }
}

/// Шпион-публикатор: копит всё опубликованное.
private final class SpyPublisher: DomainEventPublisher {
    private(set) var published: [DomainEvent] = []

    func publish(events: [DomainEvent]) {
        published.append(contentsOf: events)
    }
}

@Suite("Декоратор рассылки событий")
struct EventDispatchingRepositoryTests {

    @Test("После сохранения события агрегата уходят в публикатор и очищаются")
    func publishesOnSave() {
        let inner = InMemoryThingRepository()
        let publisher = SpyPublisher()
        let repository = EventDispatchingRepository(wrapping: inner, publisher: publisher)

        let thing = Thing(id: ThingId(value: "a"))
        thing.record(event: HappenedEvent(tag: "one"))
        thing.record(event: HappenedEvent(tag: "two"))

        let saved = repository.save(entity: thing)

        #expect(inner.saveCount == 1) // делегировал во wrapped
        #expect(publisher.published.count == 2) // выпустил оба события
        #expect(saved.domainEvents.isEmpty) // releaseEvents очистил очередь
    }

    @Test("Без событий публикатор зовётся вхолостую, персистентность идёт")
    func savesWithoutEvents() {
        let inner = InMemoryThingRepository()
        let publisher = SpyPublisher()
        let repository = EventDispatchingRepository(wrapping: inner, publisher: publisher)

        repository.save(entity: Thing(id: ThingId(value: "b")))

        #expect(inner.saveCount == 1)
        #expect(publisher.published.isEmpty)
    }

    @Test("find проксируется во wrapped без рассылки")
    func findProxies() {
        let inner = InMemoryThingRepository()
        let publisher = SpyPublisher()
        let repository = EventDispatchingRepository(wrapping: inner, publisher: publisher)

        let thing = Thing(id: ThingId(value: "c"))
        repository.save(entity: thing)

        #expect(repository.find(id: ThingId(value: "c")) === thing)
        #expect(repository.find(id: ThingId(value: "missing")) == nil)
    }
}
