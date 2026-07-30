/**
 `SwiftApplication` — удобный вход сборки контекста, наш аналог `SpringApplication.run`. Как в Spring
 Boot, где `SpringApplication.run` есть надстройка над «руками собери `AnnotationConfigApplicationContext`
 и вызови `refresh`»: поднимает контекст из готовых определений бинов и возвращает его уже запущенным
 (заливку определений и `refresh` делает сам конструктор контекста). Не сущность со временем жизни, а
 точка запуска — потому `enum` без инстанса. Generic и без изоляции, как сам контекст: держать и
 резолвить его вызыватель волен на своём акторе.
 */
public enum SwiftApplication {
    /// Поднять контекст из определений (скан `@Component` + `@Configuration`-фабрики) и вернуть его
    /// запущенным — аналог `SpringApplication.run(...)`. Бросает при кривой проводке графа, чтобы
    /// вызыватель упал на старте (fail-fast).
    ///
    /// Отдаёт `ConfigurableApplicationContext`: тот, кто контекст ПОДНЯЛ, вправе его и свернуть
    /// (`close`) — как `SpringApplication.run` возвращает `ConfigurableApplicationContext`. Дальше по
    /// коду его раздают уже как `ApplicationContext`, только для чтения.
    public static func run(definitions: [BeanDefinitionHolder]) throws -> ConfigurableApplicationContext {
        try AnnotationConfigApplicationContext(definitions: definitions)
    }
}
