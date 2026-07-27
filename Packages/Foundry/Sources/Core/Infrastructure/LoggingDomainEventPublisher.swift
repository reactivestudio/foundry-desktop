import os

/**
 Заглушка публикатора событий — просто ЛОГИРУЕТ каждое событие, никуда его не рассылая.
 Нужна, чтобы собрать и увидеть весь шов (`EventDispatchingRepository` → публикатор) ещё
 до появления настоящей шины и подписчиков. Реальный адаптер (`NotificationCenter`,
 очередь, transactional outbox) заменит её в корне композиции, не трогая ни домен, ни
 декоратор. Категория лога `domain` заведена в `FeatureLog`.
 */
public final class LoggingDomainEventPublisher: DomainEventPublisher {
    public init() {}

    public func publish(events: [DomainEvent]) {
        for event in events {
            FeatureLog.domain.debug("Domain event: \(String(describing: event), privacy: .public)")
        }
    }
}
