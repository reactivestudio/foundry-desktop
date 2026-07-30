/**
 Spring `BeanDefinition` — РЕЦЕПТ бина (метаданные), не объект. У нас иммутабельный value:
 пост-процессинг определений (BFPP) — на компиляции, рантайм-сеттеры Spring не нужны. Имени тут
 НЕТ: имя это ключ в `BeanDefinitionRegistry`, определение своего имени не знает (как в Spring).
 */
public struct BeanDefinition {
    /// Конкретный тип бина. Spring: `beanClassName` (String) — у нас метатип.
    public let beanType: Any.Type
    /// Область жизни. Spring: `getScope()`.
    public let scope: Scope
    /// Ленивая инициализация ПО ВОЛЕ АВТОРА — исключает бин из жадной преинстанциации.
    /// Spring: `isLazyInit()` (`@Lazy`). Кодоген его не выставляет: сейчас это ручка для
    /// определений, собранных руками (`@Configuration`, тесты).
    public let isLazyInit: Bool
    /**
     Сборка требует главного актора (сам тип `@MainActor` либо ТРАНЗИТИВНО зависит от такого) —
     тоже исключает бин из жадной преинстанциации, но по другой причине, чем `isLazyInit`: не автор
     так решил, а система типов. Аналога в Spring нет — в Java у конструктора нет изоляции; это цена
     Swift-конкурентности: актор `refresh` не гарантирован, а изолированный конструктор можно позвать
     только на своём акторе. Такой бин строится при резолве — который вызыватель обязан делать на
     главном акторе (см. `SwiftApplication`). Выставляет кодоген, считая замыкание по графу
     зависимостей: иначе не-`@MainActor` бин с `@MainActor`-зависимостью попал бы в жадную сборку и
     уронил бы процесс трапом `assumeIsolated` вместо ошибки.
     */
    public let isMainActorConfined: Bool
    /// Приоритетный кандидат при неоднозначности по типу. Spring: `isPrimary()`.
    public let isPrimary: Bool
    /**
     Типы, под которые бин подходит: сам тип + ТРАНЗИТИВНОЕ замыкание супертипов и протоколов.
     В Spring это выводит рефлексия (`ResolvableType`) в рантайме; в Swift рефлексии по
     конформансам нет, поэтому замыкание считает сканер на компиляции, а явные порты `@Component`
     дописывают невидимое сканеру.
     */
    public let targetTypes: [Any.Type]
    /**
     Колбэк, которым контейнер СТРОИТ бин (Spring 6 `setInstanceSupplier`). Получает фабрику,
     чтобы вытащить аргументы конструктора. Это единственное, что обязан дать кодоген вместо
     рефлексивного вызова конструктора — переходник `{ ctx in Foo(bar: try ctx.getBean(...)) }`.
     */
    public let instanceSupplier: (BeanFactory) throws -> Any

    public init(
        beanType: Any.Type,
        scope: Scope = .singleton,
        isLazyInit: Bool = false,
        isMainActorConfined: Bool = false,
        isPrimary: Bool = false,
        targetTypes: [Any.Type],
        instanceSupplier: @escaping (BeanFactory) throws -> Any
    ) {
        self.beanType = beanType
        self.scope = scope
        self.isLazyInit = isLazyInit
        self.isMainActorConfined = isMainActorConfined
        self.isPrimary = isPrimary
        self.targetTypes = targetTypes
        self.instanceSupplier = instanceSupplier
    }
}
