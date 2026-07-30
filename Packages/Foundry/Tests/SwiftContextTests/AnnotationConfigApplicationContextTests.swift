import SwiftContext
import Testing

private final class Widget {}

@Suite("AnnotationConfigApplicationContext")
struct AnnotationConfigApplicationContextTests {
    private func widgetHolder() -> BeanDefinitionHolder {
        BeanDefinitionHolder(
            name: "widget",
            definition: BeanDefinition(
                beanType: Widget.self,
                targetTypes: [Widget.self],
                instanceSupplier: { _ in Widget() }
            )
        )
    }

    @Test("Конструктор уже собрал контекст: бины резолвятся, окружение зарегистрировано")
    func initRefreshesContext() throws {
        let context = try AnnotationConfigApplicationContext(definitions: [widgetHolder()])

        #expect(try context.getBean(ofType: Widget.self) is Widget)
        #expect(context.containsBean(name: "environment"))
    }

    @Test("Повторный refresh — честная ошибка «контекст уже собран», а не мнимый дубль имени бина")
    func secondRefreshFailsHonestly() throws {
        let context = try AnnotationConfigApplicationContext(definitions: [widgetHolder()])

        do {
            try context.refresh()
            Issue.record("повторный refresh обязан упасть")
        } catch BeansException.contextAlreadyRefreshed {
            // Ожидаемо: раньше тут вылетал beanDefinitionStore про дубль имени и отправлял
            // искать несуществующий конфликт имён.
        }
    }

    @Test("close() гасит DisposableBean в порядке, обратном созданию")
    func closeDestroysDisposablesInReverseOrder() throws {
        let journal = DestroyJournal()
        let context = try AnnotationConfigApplicationContext(definitions: [
            holder(name: "first", journal: journal),
            holder(name: "second", journal: journal),
        ])

        context.close()

        // Обратный порядок — не косметика: зависимость обязана переживать того, кто ею пользовался.
        #expect(journal.destroyed == ["second", "first"])
    }

    @Test("Резолв из закрытого контекста — ошибка, а не бин с уничтоженными зависимостями")
    func resolveFromClosedContextFails() throws {
        let context = try AnnotationConfigApplicationContext(definitions: [widgetHolder()])
        context.close()

        do {
            _ = try context.getBean(ofType: Widget.self)
            Issue.record("резолв из закрытого контекста обязан упасть")
        } catch BeansException.contextClosed {
            // Ожидаемо.
        }
    }

    @Test("Повторный close() безвреден, второй раз никого не гасит")
    func secondCloseIsHarmless() throws {
        let journal = DestroyJournal()
        let context = try AnnotationConfigApplicationContext(definitions: [
            holder(name: "only", journal: journal),
        ])

        context.close()
        context.close()

        #expect(journal.destroyed == ["only"])
    }

    private func holder(name: String, journal: DestroyJournal) -> BeanDefinitionHolder {
        BeanDefinitionHolder(
            name: name,
            definition: BeanDefinition(
                beanType: Closeable.self,
                targetTypes: [],
                instanceSupplier: { _ in Closeable(name: name, journal: journal) }
            )
        )
    }
}

/// Куда бины пишут факт своего гашения — по этому списку виден ПОРЯДОК, а не только сам факт.
private final class DestroyJournal {
    var destroyed: [String] = []
}

private final class Closeable: DisposableBean {
    private let name: String
    private let journal: DestroyJournal

    init(name: String, journal: DestroyJournal) {
        self.name = name
        self.journal = journal
    }

    func destroy() throws {
        journal.destroyed.append(name)
    }
}
