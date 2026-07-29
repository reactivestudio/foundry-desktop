/// Определение бина, вычитанное сканом исходника (точное имя из Spring — `ScannedGenericBeanDefinition`,
/// определение, собранное при скане класспаса, а не рефлексией готового класса). `module` — для
/// импортов генерата; `concreteType` — что конструировать; `name` — имя бина;
/// `scope`/`targetTypes`/`dependencies` кладутся в `BeanDefinition`. `targetTypes` = транзитивное
/// замыкание супертипов (сам тип + все выразимые как `T.self` протоколы/классы цепочки, включая
/// конкретные дженерик-инстанциации вроде `PlistRepository<PreferenceSnapshot>`), которое сканер
/// считает по всему исходнику — компиляционная замена рантайм-рефлексии Spring.
public struct ScannedBeanDefinition: Equatable, Sendable {
    public let module: String
    public let concreteType: String
    public let name: String
    public let scope: String
    public let isPrimary: Bool
    public let targetTypes: [String]
    public let dependencies: [DependencyDescriptor]

    public init(
        module: String,
        concreteType: String,
        name: String,
        scope: String = "singleton",
        isPrimary: Bool = false,
        targetTypes: [String] = [],
        dependencies: [DependencyDescriptor] = []
    ) {
        self.module = module
        self.concreteType = concreteType
        self.name = name
        self.scope = scope
        self.isPrimary = isPrimary
        self.targetTypes = targetTypes
        self.dependencies = dependencies
    }
}
