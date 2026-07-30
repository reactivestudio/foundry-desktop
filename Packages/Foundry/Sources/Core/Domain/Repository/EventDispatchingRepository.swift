/**
 Декоратор репозитория, рассылающий события после сохранения — тот самый «единый шов»
 для агрегатов с событиями, но через КОМПОЗИЦИЮ, а не через protocol-extension default.
 Дефолт в `extension Repository where Aggregate: Dispatchable` был бы ловушкой: методы
 extension диспетчеризуются статически, и объявленный в конкретном репозитории `save`
 молча перекрыл бы дефолт — события то рассылались бы, то нет. Здесь же вызов идёт через
 хранимый `wrapped` (динамически), поэтому теряться нечему.

 Оборачивает ЛЮБОЙ `Repository`, чей агрегат умеет копить события (`Dispatchable`), и
 добавляет к его `save` один шаг: забрать события у сохранённого агрегата и отдать
 публикатору. `find` проксируется как есть. Порядок «сначала persist, потом publish»
 намеренный — наружу уходят только зафиксированные изменения. Собирается в корне
 композиции: `EventDispatchingRepository(wrapping: plistRepository, publisher: ...)`.
 */
public final class EventDispatchingRepository<Wrapped: Repository>: Repository
where Wrapped.Aggregate: Dispatchable {
    private let wrapped: Wrapped
    private let publisher: DomainEventPublisher

    public init(wrapping wrapped: Wrapped, publisher: DomainEventPublisher) {
        self.wrapped = wrapped
        self.publisher = publisher
    }

    public func find(id: Wrapped.Identifier) -> Wrapped.Aggregate? {
        wrapped.find(id: id)
    }

    @discardableResult
    public func save(entity: Wrapped.Aggregate) -> Wrapped.Aggregate {
        let saved = wrapped.save(entity: entity)
        publisher.publish(events: saved.releaseEvents())

        return saved
    }
}
