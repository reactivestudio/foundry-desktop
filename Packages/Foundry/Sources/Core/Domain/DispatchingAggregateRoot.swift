/**
 Корень агрегата С доменными событиями — общий словарь тактического DDD. Расширяет
 плоский `AggregateRoot` очередью событий и реализует `Dispatchable`. Использовать для
 агрегатов, чьи изменения должны публиковаться наружу; если события не нужны — брать
 плоский `AggregateRoot`. Один тип — один файл.
 */
open class DispatchingAggregateRoot<ID: Hashable>: AggregateRoot<ID>, Dispatchable {
    private var pendingEvents: [DomainEvent] = []

    public var domainEvents: [DomainEvent] {
        pendingEvents
    }

    public func record(event: DomainEvent) {
        pendingEvents.append(event)
    }

    public func releaseEvents() -> [DomainEvent] {
        let events = pendingEvents
        pendingEvents = []

        return events
    }
}
