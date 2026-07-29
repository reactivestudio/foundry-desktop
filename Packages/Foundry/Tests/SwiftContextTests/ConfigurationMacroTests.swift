import SwiftContext
import Testing

private struct Threshold {
    let value: Int
}

private protocol Gauge {
    func reading() -> Int
}

private struct RealGauge: Gauge {
    let limit: Int
    func reading() -> Int { limit }
}

// Ссылочный бин без зависимостей — для проверки синглтон-скоупа по идентичности.
private final class Ledger {
    init() {}
}

// `@Configuration` с `@Bean`: без зависимостей, с зависимостью на другой бин, и класс-синглтон —
// проверяем, что макрос даёт `definitions()`, резолв идёт по возвращаемому типу и зависимость
// подставляется из контейнера.
@Configuration
private struct MeteringConfiguration {
    @Bean
    func threshold() -> Threshold {
        Threshold(value: 5)
    }

    @Bean
    func gauge(threshold: Threshold) -> Gauge {
        RealGauge(limit: threshold.value)
    }

    @Bean
    func ledger() -> Ledger {
        Ledger()
    }
}

@Suite("Configuration-макрос")
struct ConfigurationMacroTests {
    private func assembledFactory() throws -> DefaultListableBeanFactory {
        let factory = DefaultListableBeanFactory()
        for holder in MeteringConfiguration().definitions() {
            try factory.registerBeanDefinition(name: holder.name, beanDefinition: holder.definition)
        }

        return factory
    }

    @Test("@Bean-методы дают бины по возвращаемому типу, зависимость резолвится")
    func beansRegisterByReturnTypeWithDependencies() throws {
        let factory = try assembledFactory()

        #expect(try factory.getBean(ofType: Threshold.self).value == 5)
        #expect(try factory.getBean(ofType: Gauge.self).reading() == 5)
    }

    @Test("@Bean-скоуп синглтон: тот же инстанс на повторный резолв")
    func beanIsSingleton() throws {
        let factory = try assembledFactory()

        #expect(try factory.getBean(ofType: Ledger.self) === factory.getBean(ofType: Ledger.self))
    }
}
