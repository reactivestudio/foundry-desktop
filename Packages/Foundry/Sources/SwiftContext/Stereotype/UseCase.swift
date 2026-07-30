/// Стереотип-бин слоя **Application**, ЧАСТНЫЙ СЛУЧАЙ [`ApplicationService`]: тип, несущий РОВНО
/// ОДИН сценарий — одна публичная операция (плюс конструктор внедрения). Ради этого и заводится
/// отдельная пометка: она читается как обещание «здесь одна причина меняться», и его видно на глаз —
/// появилась вторая операция, значит это уже `@ApplicationService`, а не use-case.
///
/// Семантически для контейнера это то же, что `@ApplicationService` (скан трактует одинаково);
/// различие — для читателя и для ревью границ.
///
/// Не Spring-стереотип (там всё это `@Service`) — делим сознательно, точность DDD дороже
/// буквальности Spring. Скоуп — `singleton` по умолчанию.
@attached(peer)
public macro UseCase(name: String? = nil, scope: Scope = .singleton) =
    #externalMacro(module: "SwiftContextMacros", type: "ComponentMacro")
