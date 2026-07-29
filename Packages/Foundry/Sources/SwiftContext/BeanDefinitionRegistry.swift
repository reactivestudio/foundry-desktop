/**
 Spring `BeanDefinitionRegistry` — реестр рецептов (`имя → BeanDefinition`). Наполняется один раз
 на старте из сгенерированного списка, дальше фактически заморожен (рантайм-BFPP у нас нет).
 */
public protocol BeanDefinitionRegistry: AliasRegistry {
    /// Зарегистрировать определение под именем. Кидает при дубликате (дефолт Spring Boot —
    /// overriding запрещён). Spring: `registerBeanDefinition(String, BeanDefinition)`.
    func registerBeanDefinition(name: String, beanDefinition: BeanDefinition) throws
    /// Убрать определение. Кидает, если имени нет. Spring: `removeBeanDefinition(String)`.
    func removeBeanDefinition(name: String) throws
    /// Определение по имени. Кидает, если нет. Spring: `getBeanDefinition(String)`.
    func getBeanDefinition(name: String) throws -> BeanDefinition
    /// Есть ли определение. Spring: `containsBeanDefinition(String)`.
    func containsBeanDefinition(name: String) -> Bool
    /// Все имена определений. Spring: `getBeanDefinitionNames()`.
    func getBeanDefinitionNames() -> [String]
    /// Число определений. Spring: `getBeanDefinitionCount()`.
    var beanDefinitionCount: Int { get }
    /// Занято ли имя (определением или псевдонимом). Spring: `isBeanNameInUse(String)`.
    func isBeanNameInUse(name: String) -> Bool
}
