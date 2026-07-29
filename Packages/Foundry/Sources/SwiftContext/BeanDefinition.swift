/**
 Spring `BeanDefinition` — РЕЦЕПТ бина (метаданные), не объект. У нас иммутабельный value:
 пост-процессинг определений (BFPP) — на компиляции, рантайм-сеттеры Spring не нужны. Имени тут
 НЕТ: имя это ключ в `BeanDefinitionRegistry`, определение своего имени не знает (как в Spring).
 */
public struct BeanDefinition {
    /// Конкретный тип бина. Spring: `beanClassName` (String) — у нас метатип.
    public let beanType: Any.Type
    /// Область жизни. Spring: `getScope()`.
    public let scope: BeanScope
    /// Ленивая инициализация — исключает бин из жадной преинстанциации. Spring: `isLazyInit()`.
    public let isLazyInit: Bool
    /// Приоритетный кандидат при неоднозначности по типу. Spring: `isPrimary()`.
    public let isPrimary: Bool
    /// Явные зависимости-предшественники (по имени). Spring: `getDependsOn()`.
    public let dependsOn: [String]
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
        scope: BeanScope = .singleton,
        isLazyInit: Bool = false,
        isPrimary: Bool = false,
        dependsOn: [String] = [],
        targetTypes: [Any.Type],
        instanceSupplier: @escaping (BeanFactory) throws -> Any
    ) {
        self.beanType = beanType
        self.scope = scope
        self.isLazyInit = isLazyInit
        self.isPrimary = isPrimary
        self.dependsOn = dependsOn
        self.targetTypes = targetTypes
        self.instanceSupplier = instanceSupplier
    }
}
