/// Стереотип-бин (аналог Spring `@Component`): помечает класс-реализацию, чтобы скан-плагин собрал
/// её в контейнер. Чистый МАРКЕР — ничего не разворачивает: определение бина (имя, скоуп,
/// `targetTypes`, supplier) целиком генерит `BeanScan` по результату скана, ровно как `@ComponentScan`
/// не пишет код в сам класс. Цепочку наследования (какие контракты закрывает тип) скан строит сам по
/// исходнику — заявлять её в атрибуте не нужно. `name` задаёт имя бина (иначе —
/// декапитализированное имя типа, как в Spring). Скоуп — `singleton` по умолчанию.
@attached(peer)
public macro Component(name: String? = nil, scope: Scope = .singleton) =
    #externalMacro(module: "SwiftContextMacros", type: "ComponentMacro")
