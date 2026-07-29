/**
 Spring `ListableBeanFactory` — расширяет `BeanFactory` перечислением по типу (база коллекций
 `List<Interface>`). Матчит по МЕТАДАННЫМ (`targetTypes`), без инстанцирования кандидатов —
 как Spring с `allowEagerInit=false`.
 */
public protocol ListableBeanFactory: BeanFactory {
    /// Есть ли определение с таким именем. Spring: `containsBeanDefinition(String)`.
    func containsBeanDefinition(name: String) -> Bool
    /// Число определений. Spring: `getBeanDefinitionCount()`.
    var beanDefinitionCount: Int { get }
    /// Все имена определений (в порядке регистрации). Spring: `getBeanDefinitionNames()`.
    func getBeanDefinitionNames() -> [String]
    /// Имена бинов, подходящих по типу (в порядке регистрации). Spring: `getBeanNamesForType(Class)`.
    func getBeanNames(forType type: Any.Type) -> [String]
    /// Карта `имя → бин` для всех подходящих по типу. Spring: `Map<String,T> getBeansOfType(Class<T>)`.
    func getBeans<T>(ofType type: T.Type) throws -> [String: T]
}
