/**
 Область жизни бина — аналог Spring `@Scope` (там строкой "singleton"/"prototype"). Берём enum
 вместо stringly-typed: смысл тот же, но проверяется компилятором. Один тип на всё — и аргумент
 `@Component(scope:)`, и поле `BeanDefinition.scope`, по которому фабрика решает: `singleton` — один
 на контейнер, `prototype` — новый на каждый резолв. Кастомные скоупы (request/…) в Spring делаются
 стратегией; её пока не заводим.
 */
public enum Scope: Sendable {
    /// Один экземпляр на контейнер (дефолт Spring). Кэшируется в `SingletonBeanRegistry`.
    case singleton
    /// Новый экземпляр на каждый резолв. Не кэшируется.
    case prototype
}
