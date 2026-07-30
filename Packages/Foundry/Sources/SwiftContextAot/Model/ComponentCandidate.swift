/// Кандидат в бины: помеченный стереотипом (`@Component` или специализация по слою —
/// `@DomainService`/`@ApplicationService`/`@UseCase`/`@Repository`/`@Store`) тип как он прочитан из
/// исходника, ДО вычисления замыкания супертипов (Spring зовёт «candidate component» то, что нашёл
/// скан класспаса до доводки до полного `BeanDefinition`). `name` — как написан в `@Component(name:)`
/// или `nil` (тогда сканер выведет дефолт из имени типа); `scope` — из `(scope:)`; `isMainActor` —
/// помечен ли тип `@MainActor` (тогда его конструктор изолирован на главном акторе); `isLazyInit` и
/// `isPrimary` — из `@Lazy`/`@Primary`; `dependencies` — параметры конструктора внедрения.
struct ComponentCandidate {
    let module: String
    let concreteType: String
    let name: String?
    let scope: String
    let isMainActor: Bool
    let isLazyInit: Bool
    let isPrimary: Bool
    let dependencies: [DependencyDescriptor]
}
