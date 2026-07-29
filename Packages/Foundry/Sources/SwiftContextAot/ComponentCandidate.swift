/// Кандидат в бины: помеченный `@Component` тип как он прочитан из исходника, ДО вычисления
/// замыкания супертипов (Spring зовёт «candidate component» то, что нашёл скан класспаса до
/// доводки до полного `BeanDefinition`). `name` — как написан в `@Component(name:)` или `nil`
/// (тогда сканер выведет дефолт из имени типа); `scope` — из `@Component(scope:)`; `dependencies`
/// — параметры выбранного init'а.
struct ComponentCandidate {
    let module: String
    let concreteType: String
    let name: String?
    let scope: String
    let dependencies: [DependencyDescriptor]
}
