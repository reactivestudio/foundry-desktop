/**
 Spring `BeansException` (в Java unchecked). У нас — бросаемый enum с кейсами-аналогами
 подклассов: `getBean` КИДАЕТ, а не возвращает `nil` (как в Spring); fail-fast на старте ловит
 Bootstrap.
 */
public enum BeansException: Error {
    /// Нет бина, подходящего по типу. Spring: `NoSuchBeanDefinitionException(Class)`.
    case noSuchBeanDefinition(Any.Type)
    /// Нет бина с таким именем. Spring: `NoSuchBeanDefinitionException(String)`.
    case noSuchBeanDefinitionNamed(String)
    /// По типу подходит ≥2 кандидата и ни один не `@Primary`. Spring: `NoUniqueBeanDefinitionException`.
    case noUniqueBeanDefinition(Any.Type, candidates: [String])
    /// Бин есть, но не приводится к требуемому типу. Spring: `BeanNotOfRequiredTypeException`.
    case beanNotOfRequiredType(name: String, required: Any.Type, actual: Any.Type)
    /// Ошибка при сборке бина (пробрасывает причину из supplier'а). Spring: `BeanCreationException`.
    case beanCreation(name: String, cause: Error)
    /// Проблема регистрации определения (напр. дубликат имени). Spring: `BeanDefinitionStoreException`.
    case beanDefinitionStore(name: String, reason: String)
    /// Цикл в конструкторах: бин уже в процессе сборки. Spring: `BeanCurrentlyInCreationException`.
    case beanCurrentlyInCreation(name: String)
}
