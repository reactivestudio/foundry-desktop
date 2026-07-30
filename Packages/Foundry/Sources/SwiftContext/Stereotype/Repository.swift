/// Стереотип-бин слоя Infrastructure (аналог Spring `@Repository`): семантическая специализация
/// `@Component` для адаптеров-хранилищ (реализаций портов-репозиториев). В Spring `@Repository`
/// вдобавок включает трансляцию исключений хранилища — у нас это ЧИСТО семантический маркер, скан
/// подхватывает его наравне с `@Component`. Определение бина генерит `BeanScan`; сам макрос ничего не
/// разворачивает. `name`/`scope` — как у `@Component` (по умолчанию — декап-имя типа и `singleton`).
@attached(peer)
public macro Repository(name: String? = nil, scope: Scope = .singleton) =
    #externalMacro(module: "SwiftContextMacros", type: "ComponentMacro")
