/**
 Spring `AliasRegistry` — родитель `BeanDefinitionRegistry`: бин может иметь несколько имён.
 У нас имя = декапитализированный тип (или явное из `@Component`/`@Bean`), псевдонимов пока нет —
 реализация тривиальна; держим ради верности иерархии.
 */
public protocol AliasRegistry {
    /// Завести псевдоним для канонического имени. Spring: `registerAlias(String, String)`.
    func registerAlias(name: String, alias: String)
    /// Убрать псевдоним. Spring: `removeAlias(String)`.
    func removeAlias(alias: String)
    /// Является ли имя псевдонимом. Spring: `isAlias(String)`.
    func isAlias(name: String) -> Bool
    /// Псевдонимы канонического имени. Spring: `getAliases(String)`.
    func getAliases(name: String) -> [String]
}
