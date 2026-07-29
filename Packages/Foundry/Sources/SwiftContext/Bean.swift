/// Метод-фабрика бина внутри `@Configuration` (аналог `@Bean` Spring). Сам по себе ничего
/// не разворачивает — это маркер, который читает `@Configuration`: он и генерит регистрацию
/// по возвращаемому типу метода. Метод остаётся обычным — `@Configuration` зовёт его при
/// сборке контейнера, подставляя параметры резолвом из контейнера. `name` задаёт имя бина
/// (иначе — имя метода, как в Spring).
@attached(peer)
public macro Bean(name: String? = nil) =
    #externalMacro(module: "SwiftContextMacros", type: "BeanMacro")
