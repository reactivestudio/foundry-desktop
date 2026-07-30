/**
 `AnnotationConfigApplicationContext` — прикладной контекст, собираемый из аннотаций (как в Spring:
 контекст, что принимает готовые определения бинов от скана `@Component` и `@Configuration`-фабрик).
 КОМПОЗИЦИЕЙ держит `DefaultListableBeanFactory` и делегирует ему весь резолв (Spring так же:
 `GenericApplicationContext` хранит `DefaultListableBeanFactory` и проксирует к нему `getBean`). Своё
 у контекста — окружение и `refresh`: регистрация окружения синглтоном, заливка определений в реестр
 и жадная преинстанциация. Прикладной bootstrap работает только с контекстом, фабрику руками не трогает.

 Изоляция — как у самой фабрики (`DefaultListableBeanFactory`): от использования на одном акторе,
 внутреннего замка нет; bootstrap держит и резолвит контекст на главном акторе.
 */
public final class AnnotationConfigApplicationContext {
    private let beanFactory = DefaultListableBeanFactory()
    private let holders: [BeanDefinitionHolder]
    /// Контекст уже собран — второй `refresh()` не поддерживаем (как `GenericApplicationContext`).
    private var isActive = false

    public let environment: Environment

    /// Конструктор из определений: окружение (env поверх дефолтов) плюс набор `BeanDefinitionHolder`
    /// от скана `@Component` и `@Configuration`-фабрик. Сразу собирает контекст (`refresh`), падая при
    /// кривой проводке на старте, — конструктор возвращает уже готовый к резолву контекст.
    public init(
        environment: Environment = .standard(),
        definitions holders: [BeanDefinitionHolder]
    ) throws {
        self.environment = environment
        self.holders = holders
        try refresh()
    }

    /// Контекст активен — собран и не закрыт. Spring проверяет это же в `assertBeanFactoryActive`
    /// перед каждым `getBean`: резолв из закрытого контекста отдал бы бин, чьи зависимости уже
    /// уничтожены, — ошибка честнее полурабочего графа.
    private func assertBeanFactoryActive() throws {
        guard isActive else {
            throw BeansException.contextClosed
        }
    }
}

// MARK: - ConfigurableApplicationContext (жизненный цикл — только владельцу)

extension AnnotationConfigApplicationContext: ConfigurableApplicationContext {
    public func refresh() throws {
        // Второй раз собирать нечего: определения уже залиты, и повторная заливка упиралась бы в
        // запрет дубля имён — ошибка про «дубль бина» вместо честной «контекст уже собран».
        // `GenericApplicationContext` в Spring так же поддерживает ровно один refresh.
        guard !isActive else {
            throw BeansException.contextAlreadyRefreshed
        }
        isActive = true
        // Окружение конфигурации — контекст авто-регистрирует его синглтоном (как Spring Boot),
        // `@Bean`/`@Component` затем внедряют его для `@Value`-семантики.
        beanFactory.registerSingleton(name: "environment", singletonObject: environment)
        for holder in holders {
            try beanFactory.registerBeanDefinition(name: holder.name, beanDefinition: holder.definition)
        }
        try beanFactory.preInstantiateSingletons()
    }

    public func close() {
        guard isActive else { return }
        isActive = false
        // Сворачивание не бросает (Spring `close()` тоже): недогашенный бин — повод сообщить, а не
        // повод оборвать закрытие. Молчать о нём нельзя, потому — в лог.
        for failure in beanFactory.destroySingletons() {
            ContextLog.destroyFailed(name: failure.name, error: failure.error)
        }
    }
}

// MARK: - BeanFactory (делегирование фабрике)

extension AnnotationConfigApplicationContext: BeanFactory {
    public func getBean(name: String) throws -> Any {
        try assertBeanFactoryActive()

        return try beanFactory.getBean(name: name)
    }

    public func getBean<T>(name: String, ofType requiredType: T.Type) throws -> T {
        try assertBeanFactoryActive()

        return try beanFactory.getBean(name: name, ofType: requiredType)
    }

    public func getBean<T>(ofType requiredType: T.Type) throws -> T {
        try assertBeanFactoryActive()

        return try beanFactory.getBean(ofType: requiredType)
    }

    public func containsBean(name: String) -> Bool {
        beanFactory.containsBean(name: name)
    }

    public func isSingleton(name: String) throws -> Bool {
        try beanFactory.isSingleton(name: name)
    }

    public func isPrototype(name: String) throws -> Bool {
        try beanFactory.isPrototype(name: name)
    }

    public func getType(name: String) throws -> Any.Type {
        try beanFactory.getType(name: name)
    }

    public func getAliases(name: String) -> [String] {
        beanFactory.getAliases(name: name)
    }
}

// MARK: - ListableBeanFactory (делегирование фабрике)

extension AnnotationConfigApplicationContext: ListableBeanFactory {
    public func containsBeanDefinition(name: String) -> Bool {
        beanFactory.containsBeanDefinition(name: name)
    }

    public var beanDefinitionCount: Int {
        beanFactory.beanDefinitionCount
    }

    public func getBeanDefinitionNames() -> [String] {
        beanFactory.getBeanDefinitionNames()
    }

    public func getBeanNames(forType type: Any.Type) -> [String] {
        beanFactory.getBeanNames(forType: type)
    }

    public func getBeans<T>(ofType type: T.Type) throws -> [String: T] {
        try assertBeanFactoryActive()

        return try beanFactory.getBeans(ofType: type)
    }
}
