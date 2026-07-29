import SwiftContext
import Testing

// MARK: - Пробные типы

// Цепочка наследования для резолва «по любому типу»: Dog: Pet, Pet: Animal.
private protocol Animal {}
private protocol Pet: Animal {}
private final class Dog: Pet {}

// Порт с двумя реализациями — для @Primary/неоднозначности/коллекций.
private protocol Engine {}
private final class V8: Engine {}
private final class Diesel: Engine {}

// Зависимость конструктора — резолвится supplier'ом из фабрики.
private final class Car {
    let engine: Engine
    init(engine: Engine) { self.engine = engine }
}

// Взаимный цикл в конструкторах.
private final class Alpha {}
private final class Beta {}

@Suite("DefaultListableBeanFactory")
struct DefaultListableBeanFactoryTests {
    private func dogDefinition(scope: BeanScope = .singleton) -> BeanDefinition {
        BeanDefinition(
            beanType: Dog.self,
            scope: scope,
            targetTypes: [Dog.self, Pet.self, Animal.self],
            instanceSupplier: { _ in Dog() }
        )
    }

    private func v8Definition(isPrimary: Bool = false) -> BeanDefinition {
        BeanDefinition(
            beanType: V8.self,
            isPrimary: isPrimary,
            targetTypes: [V8.self, Engine.self],
            instanceSupplier: { _ in V8() }
        )
    }

    private func dieselDefinition() -> BeanDefinition {
        BeanDefinition(
            beanType: Diesel.self,
            targetTypes: [Diesel.self, Engine.self],
            instanceSupplier: { _ in Diesel() }
        )
    }

    @Test("Резолв по имени возвращает бин")
    func resolvesByName() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "dog", beanDefinition: dogDefinition())

        #expect(try context.getBean(name: "dog") is Dog)
    }

    @Test("Резолв по ЛЮБОМУ типу цепочки — один и тот же объект")
    func resolvesByAnyTypeInChain() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "dog", beanDefinition: dogDefinition())

        let byConcrete = try context.getBean(ofType: Dog.self)
        let byPet = try context.getBean(ofType: Pet.self)
        let byAnimal = try context.getBean(ofType: Animal.self)

        #expect(byConcrete as AnyObject === byPet as AnyObject)
        #expect(byPet as AnyObject === byAnimal as AnyObject)
    }

    @Test("Синглтон — один экземпляр на все резолвы")
    func singletonIsShared() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "dog", beanDefinition: dogDefinition())

        #expect(try context.getBean(ofType: Dog.self) === context.getBean(ofType: Dog.self))
    }

    @Test("Прототип — новый экземпляр на каждый резолв")
    func prototypeIsFresh() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "dog", beanDefinition: dogDefinition(scope: .prototype))

        #expect(try context.getBean(ofType: Dog.self) !== context.getBean(ofType: Dog.self))
    }

    @Test("Внедрение зависимости конструктора через supplier")
    func injectsConstructorDependency() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "v8", beanDefinition: v8Definition())
        try context.registerBeanDefinition(
            name: "car",
            beanDefinition: BeanDefinition(
                beanType: Car.self,
                targetTypes: [Car.self],
                instanceSupplier: { factory in Car(engine: try factory.getBean(ofType: Engine.self)) }
            )
        )

        #expect(try context.getBean(ofType: Car.self).engine is V8)
    }

    @Test("@Primary разрешает неоднозначность по типу")
    func primaryWinsAmbiguity() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "v8", beanDefinition: v8Definition(isPrimary: true))
        try context.registerBeanDefinition(name: "diesel", beanDefinition: dieselDefinition())

        #expect(try context.getBean(ofType: Engine.self) is V8)
    }

    @Test("Две реализации без @Primary — noUniqueBeanDefinition")
    func ambiguityWithoutPrimaryThrows() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "v8", beanDefinition: v8Definition())
        try context.registerBeanDefinition(name: "diesel", beanDefinition: dieselDefinition())

        #expect(throws: BeansException.self) {
            _ = try context.getBean(ofType: Engine.self)
        }
    }

    @Test("Нет бина по типу — noSuchBeanDefinition")
    func missingTypeThrows() {
        let context = DefaultListableBeanFactory()

        #expect(throws: BeansException.self) {
            _ = try context.getBean(ofType: Engine.self)
        }
    }

    @Test("Коллекция: все реализации порта видны по имени и как карта")
    func collectionSeesAllImplementations() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "v8", beanDefinition: v8Definition())
        try context.registerBeanDefinition(name: "diesel", beanDefinition: dieselDefinition())

        #expect(context.getBeanNames(forType: Engine.self).count == 2)
        #expect(try context.getBeans(ofType: Engine.self).count == 2)
    }

    @Test("Дубликат имени — beanDefinitionStore")
    func duplicateNameThrows() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "dog", beanDefinition: dogDefinition())

        #expect(throws: BeansException.self) {
            try context.registerBeanDefinition(name: "dog", beanDefinition: dogDefinition())
        }
    }

    @Test("Цикл в конструкторах — beanCurrentlyInCreation")
    func constructorCycleThrows() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(
            name: "alpha",
            beanDefinition: BeanDefinition(
                beanType: Alpha.self,
                targetTypes: [Alpha.self],
                instanceSupplier: { factory in _ = try factory.getBean(name: "beta"); return Alpha() }
            )
        )
        try context.registerBeanDefinition(
            name: "beta",
            beanDefinition: BeanDefinition(
                beanType: Beta.self,
                targetTypes: [Beta.self],
                instanceSupplier: { factory in _ = try factory.getBean(name: "alpha"); return Beta() }
            )
        )

        #expect(throws: BeansException.self) {
            _ = try context.getBean(name: "alpha")
        }
    }

    @Test("Жадная сборка строит синглтоны заранее")
    func preInstantiateBuildsSingletons() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(name: "dog", beanDefinition: dogDefinition())

        #expect(!context.containsSingleton(name: "dog"))
        try context.preInstantiateSingletons()
        #expect(context.containsSingleton(name: "dog"))
    }

    @Test("Жадная сборка падает сразу при кривой проводке")
    func preInstantiateFailsFast() throws {
        let context = DefaultListableBeanFactory()
        try context.registerBeanDefinition(
            name: "car",
            beanDefinition: BeanDefinition(
                beanType: Car.self,
                targetTypes: [Car.self],
                instanceSupplier: { factory in Car(engine: try factory.getBean(ofType: Engine.self)) }
            )
        )

        #expect(throws: BeansException.self) {
            try context.preInstantiateSingletons()
        }
    }
}
