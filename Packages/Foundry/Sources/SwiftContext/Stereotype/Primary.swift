/// Приоритетный кандидат при резолве по типу (аналог Spring `@Primary`): когда типу подходят
/// несколько бинов, победит помеченный — вместо ошибки `noUniqueBeanDefinition`. Ровно один `@Primary`
/// на тип-контракт: два приоритетных снова неоднозначность.
///
/// Чистый МАРКЕР: определение бина (`isPrimary`) генерит `BeanScan` по результату скана.
@attached(peer)
public macro Primary() =
    #externalMacro(module: "SwiftContextMacros", type: "ComponentMacro")
