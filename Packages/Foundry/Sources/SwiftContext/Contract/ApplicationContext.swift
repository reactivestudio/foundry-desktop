/**
 `ApplicationContext` — контейнер прикладного уровня (как в Spring): поверх `ListableBeanFactory`
 добавляет окружение (`Environment`). В Spring это отдельный объект, который КОМПОЗИЦИЕЙ держит
 `DefaultListableBeanFactory` и делегирует ему резолв, а сам берёт на себя сборку графа — поэтому
 прикладной bootstrap не трогает фабрику руками, а работает с контекстом.

 Контракт ТОЛЬКО ДЛЯ ЧТЕНИЯ — ровно как в Spring: `refresh`/`close` живут в
 `ConfigurableApplicationContext`, и прикладной код, которому дали `ApplicationContext`, физически
 не может пересобрать или закрыть контейнер под собой. Разделение не косметика: кто получает
 контекст, чтобы читать бины, не должен иметь власти над его жизненным циклом.
 */
public protocol ApplicationContext: ListableBeanFactory {
    /// Окружение конфигурации (env поверх дефолтов), доступное бинам для `@Value`-семантики.
    var environment: Environment { get }
}
