/**
 Порт публикации доменных событий — контракт в Domain, реализация в Infrastructure
 (Infra → Application). Куда именно уходят события (шина, `NotificationCenter`, лог,
 outbox) — забота адаптера; домен знает лишь «опубликовать пачку». Пачкой, а не по
 одному, потому что события одной транзакции выпускаются вместе: `releaseEvents()`
 отдаёт массив, накопленный за одну мутацию агрегата.
 */
public protocol DomainEventPublisher {
    func publish(events: [DomainEvent])
}
