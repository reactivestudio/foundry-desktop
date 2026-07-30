/// `@Configuration`-тип, найденный сканом. В Spring `@Configuration` — это `@Component`, и скан
/// класспаса подхватывает конфиги наравне с компонентами; их `@Bean`-методы становятся бинами. У нас
/// так же: сканер собирает конфиги отдельным списком, а генерат подмешивает их `definitions()` в
/// общий `BeanScan.definitions()` — чтобы источник определений был ОДИН (не приходилось руками
/// перечислять конфиги в bootstrap). `module` нужен генерату для импорта, `concreteType` — чтобы
/// позвать `Тип().definitions()`.
public struct ScannedConfiguration: Equatable, Sendable {
    public let module: String
    public let concreteType: String

    public init(module: String, concreteType: String) {
        self.module = module
        self.concreteType = concreteType
    }
}
