/**
 `ApplicationContext` — контейнер прикладного уровня (как в Spring): поверх `ListableBeanFactory`
 добавляет окружение (`Environment`) и жизненный цикл (`refresh`). В Spring это отдельный объект,
 который КОМПОЗИЦИЕЙ держит `DefaultListableBeanFactory` и делегирует ему резолв, а сам берёт на
 себя сборку графа — поэтому прикладной bootstrap не трогает фабрику руками, а работает с контекстом.
 */
public protocol ApplicationContext: ListableBeanFactory {
    /// Окружение конфигурации (env поверх дефолтов), доступное бинам для `@Value`-семантики.
    var environment: Environment { get }

    /// Собрать контекст: зарегистрировать окружение и определения бинов, затем жадно
    /// преинстанциировать синглтоны (аналог `AbstractApplicationContext.refresh`).
    func refresh() throws
}
