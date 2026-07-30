/**
 Spring `BeanFactory` — КОРНЕВОЙ интерфейс контейнера. Чистый lookup: про определения не знает.
 Кидает `BeansException`, а не возвращает `nil` (как в Spring). Резолв по типу — надстройка над
 `ListableBeanFactory`; здесь примитив by-name и справки о бине.
 */
public protocol BeanFactory {
    /// Бин по имени. Spring: `Object getBean(String)`.
    func getBean(name: String) throws -> Any
    /// Бин по имени с приведением к типу. Spring: `<T> T getBean(String, Class<T>)`.
    func getBean<T>(name: String, ofType requiredType: T.Type) throws -> T
    /// Единственный бин по типу. Spring: `<T> T getBean(Class<T>)`.
    func getBean<T>(ofType requiredType: T.Type) throws -> T

    /// Есть ли бин с таким именем. Spring: `containsBean(String)`.
    func containsBean(name: String) -> Bool
    /// Синглтон ли бин. Spring: `isSingleton(String)`.
    func isSingleton(name: String) throws -> Bool
    /// Прототип ли бин. Spring: `isPrototype(String)`.
    func isPrototype(name: String) throws -> Bool
    /// Тип бина по имени. Spring: `Class<?> getType(String)`.
    func getType(name: String) throws -> Any.Type
    /// Псевдонимы имени. Spring: `String[] getAliases(String)`.
    func getAliases(name: String) -> [String]
}
