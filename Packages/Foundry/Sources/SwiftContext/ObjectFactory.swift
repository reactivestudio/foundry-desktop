/**
 Spring `ObjectFactory<T>` — функциональный интерфейс: «дай объект по требованию». Отложенный
 доступ к бину. База для `ObjectProvider` и аргумент `Scope.get` (и то, и другое пока отложено —
 фиксируем только контракт).
 */
public protocol ObjectFactory<Instance> {
    associatedtype Instance
    /// Построить/достать объект. Spring: `T getObject() throws BeansException`.
    func getObject() throws -> Instance
}
