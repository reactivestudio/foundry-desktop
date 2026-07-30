/// Класс `@Configuration` Spring на Swift: тип-держатель фабрик бинов. Макрос дописывает ему
/// `definitions() -> [BeanDefinitionHolder]` — набор `BeanDefinition` по каждому `@Bean`-методу
/// (параметры метода резолвятся из контейнера — как аргументы `@Bean`-метода в Spring). Bootstrap
/// сливает их в контекст. Для бинов, которые скан `@Component` взять не может (типы
/// Foundation, кастомная сборка) — это и есть их место, ровно как `@Bean`-методы рядом с
/// `@ComponentScan`.
@attached(extension, names: named(definitions()))
public macro Configuration() =
    #externalMacro(module: "SwiftContextMacros", type: "ConfigurationMacro")
