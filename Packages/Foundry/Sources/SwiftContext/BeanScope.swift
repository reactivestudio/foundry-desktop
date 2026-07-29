/**
 Область жизни бина — аналог Spring `@Scope` (там строкой "singleton"/"prototype"). Берём enum
 вместо stringly-typed: смысл тот же, но проверяется компилятором. Кастомные скоупы (request/…)
 в Spring делаются стратегией `Scope`; её пока не заводим.
 */
public enum BeanScope: Sendable {
    /// Один экземпляр на контейнер (дефолт Spring). Кэшируется в `SingletonBeanRegistry`.
    case singleton
    /// Новый экземпляр на каждый резолв. Не кэшируется.
    case prototype
}
