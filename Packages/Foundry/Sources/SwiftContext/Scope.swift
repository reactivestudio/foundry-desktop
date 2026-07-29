/// Область жизни бина в аргументе `@Component(scope:)` (аналог Spring `@Scope`). Сканер читает её
/// текстом и кладёт в `BeanDefinition.scope` (`BeanScope`), по которой фабрика бинов решает:
/// `singleton` — один на контейнер, `prototype` — новый на каждый резолв.
public enum Scope {
    case singleton
    case prototype
}
