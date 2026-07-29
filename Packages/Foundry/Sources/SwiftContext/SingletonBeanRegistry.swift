/**
 Spring `SingletonBeanRegistry` — контракт КЭША синглтонов (отдельно от определений: сюда кладут
 и уже-готовые объекты, напр. окружение). Мьютекс Spring (`getSingletonMutex`) не тащим — изоляция
 обеспечивается использованием на одном акторе.
 */
public protocol SingletonBeanRegistry {
    /// Положить готовый синглтон под именем. Spring: `registerSingleton(String, Object)`.
    func registerSingleton(name: String, singletonObject: Any)
    /// Синглтон по имени или `nil`. Spring: `Object getSingleton(String)`.
    func getSingleton(name: String) -> Any?
    /// Есть ли синглтон с таким именем. Spring: `containsSingleton(String)`.
    func containsSingleton(name: String) -> Bool
    /// Имена всех синглтонов. Spring: `getSingletonNames()`.
    func getSingletonNames() -> [String]
    /// Число синглтонов. Spring: `getSingletonCount()`.
    var singletonCount: Int { get }
}
