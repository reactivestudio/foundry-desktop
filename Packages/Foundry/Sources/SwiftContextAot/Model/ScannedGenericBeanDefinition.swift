/// Определение бина, вычитанное сканом исходника (точное имя из Spring — `ScannedGenericBeanDefinition`,
/// определение, собранное при скане класспаса, а не рефлексией готового класса). `module` — для
/// импортов генерата; `concreteType` — что конструировать; `name` — имя бина;
/// `scope`/`targetTypes`/`dependencies` кладутся в `BeanDefinition`. `targetTypes` = транзитивное
/// замыкание супертипов (сам тип + все выразимые как `T.self` протоколы/классы цепочки, включая
/// конкретные дженерик-инстанциации вроде `Box<Item>`), которое сканер
/// считает по всему исходнику — компиляционная замена рантайм-рефлексии Spring.
///
/// Про главный актор — ДВА разных флага:
/// - `isMainActor` — САМ тип помечен `@MainActor`, его конструктор изолирован: генерат обязан звать
///   его через `MainActor.assumeIsolated`;
/// - `isMainActorConfined` — сборка требует главного актора, включая ТРАНЗИТИВНЫЙ случай (тип
///   неизолирован, но зависит от `@MainActor`-бина): такой бин нельзя пускать в жадную
///   преинстанциацию. Считает сканер замыканием по графу зависимостей; для помеченных типов он тоже
///   истинен. Без него не-`@MainActor` бин с `@MainActor`-зависимостью рушил бы процесс трапом
///   `assumeIsolated` внутри `refresh`.
///
/// `isLazyInit` (из `@Lazy`) — тоже вон из преинстанциации, но волей АВТОРА, а не системы типов;
/// `isPrimary` (из `@Primary`) — приоритет при резолве по типу, когда кандидатов несколько.
public struct ScannedGenericBeanDefinition: Equatable, Sendable {
    public let module: String
    public let concreteType: String
    public let name: String
    public let scope: String
    public let isMainActor: Bool
    public let isMainActorConfined: Bool
    public let isLazyInit: Bool
    public let isPrimary: Bool
    public let targetTypes: [String]
    public let dependencies: [DependencyDescriptor]

    public init(
        module: String,
        concreteType: String,
        name: String,
        scope: String = "singleton",
        isMainActor: Bool = false,
        isMainActorConfined: Bool = false,
        isLazyInit: Bool = false,
        isPrimary: Bool = false,
        targetTypes: [String] = [],
        dependencies: [DependencyDescriptor] = []
    ) {
        self.module = module
        self.concreteType = concreteType
        self.name = name
        self.scope = scope
        self.isMainActor = isMainActor
        self.isMainActorConfined = isMainActorConfined
        self.isLazyInit = isLazyInit
        self.isPrimary = isPrimary
        self.targetTypes = targetTypes
        self.dependencies = dependencies
    }

    /// Тот же бин с выставленным конфайнментом — сканер так помечает найденных транзитивно.
    func confinedToMainActor() -> ScannedGenericBeanDefinition {
        ScannedGenericBeanDefinition(
            module: module,
            concreteType: concreteType,
            name: name,
            scope: scope,
            isMainActor: isMainActor,
            isMainActorConfined: true,
            isLazyInit: isLazyInit,
            isPrimary: isPrimary,
            targetTypes: targetTypes,
            dependencies: dependencies
        )
    }
}
