// swift-tools-version: 6.1
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Foundry",
    platforms: [.macOS(.v15)],
    products: [
        // Bootstrap — bootstrap приложения (Spark-контейнер + корневой вид). Это
        // единственный продукт, что линкует приложение: он один знает конкретные
        // детали и сшивает контексты между собой.
        .library(name: "Bootstrap", targets: ["Bootstrap"]),
        // Замер роя на настоящей Metal-железке: swift run OrbBench
        .executable(name: "OrbBench", targets: ["OrbBench"]),
    ],
    dependencies: [
        // Пре-1.0 — пиновать версию (practices 06, пункт 1.1).
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "0.5.0"),
        // Spark — DI-контейнер, выросший из здешнего SwiftContext и вынесенный отдельной либой:
        // фреймворк общего назначения в репозитории продукта — чужой дом. Даёт и стереотипы
        // (@Component/@Configuration/@Bean), и скан-плагин; пре-1.0 — пиновать точно.
        .package(url: "https://github.com/reactivestudio/spark", exact: "0.1.1"),
        // swift-syntax — ради macro-таргета CoreMacros. Новой ветки в графе он не
        // добавляет: ровно эта версия уже пришла транзитивно со скан-плагином Spark,
        // поэтому пин ТОЧНО совпадает с его пином — расхождение развело бы две копии
        // swift-syntax. Заодно 601.x тулчейн Swift 6.2 отдаёт prebuilt-бинарём (чистая
        // сборка пакета 7 с против 38 с на 603.x, где он собирается из исходников).
        // Поднимать версию — только вместе со Spark и с проверкой, что prebuilt подхватился.
        .package(url: "https://github.com/swiftlang/swift-syntax", exact: "601.0.1"),
    ],
    targets: [
        // Верхний уровень модульности — bounded context (фича), а не технический
        // слой. Внутри каждого контекста слои DDD живут папками
        // (Domain/Application/Infrastructure/Presentation); граница КОНТЕКСТА
        // (фича↔фича) сторожится компилятором через таргеты, граница слоёв внутри —
        // дисциплина контекста. Растёт число контекстов — растёт число таргетов
        // линейно; разжиревший контекст повышается до пофичевых под-таргетов.

        // Core — ядро, справедливое для ВСЕХ контекстов: дизайн-система (токены,
        // движение, брендовый рой) и платформенные хелперы (AppKit, лог). Не знает
        // ни одного контекста.
        .target(
            name: "Core",
            dependencies: ["CoreMacros"],
            resources: [.process("DesignSystem/OrbSwarm.metal")]
        ),

        // CoreMacros — compiler-плагин тактического ядра: реализация `@Invariants`/`@Invariant`,
        // что дописывают в команды агрегата проверку инвариантов. Это единственное место пакета,
        // где живёт swift-syntax; само объявление макроса — в Core/Domain/Entity, рядом с
        // `AggregateRoot`, потому что макрос — часть его контракта, а не отдельная тема.
        .macro(
            name: "CoreMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // Setting — supporting-субдомен пользовательских настроек (имя в
        // единственном числе): агрегат `Preference` с группами-VO, порт репозитория
        // и plist-адаптер. Презентация контекста — папкой `Presentation/Setup`:
        // мастер первого запуска это НЕ отдельный контекст, а пошаговый вид тех же
        // настроек (экран в экран: агенты/расширения — будущий `Tool`, настройки —
        // `Preference`, разрешения — порт-gateway к ОС). Позже рядом ляжет второй
        // вид — окно настроек приложения. Ни от кого не зависит, кроме Core.
        .target(
            name: "Setting",
            dependencies: [
                "Core",
                // Адаптер связки с инструментами спрашивает у CLI версию — тем же
                // swift-subprocess, что и раннер агента (практики 06).
                .product(name: "Subprocess", package: "swift-subprocess"),
                // Вся DI-поверхность контекста (@Component/@Configuration/@Bean) — маркеры из
                // Spark; сборку по ним делает скан-плагин, самому контексту хватает SparkIoC.
                .product(name: "SparkIoC", package: "spark"),
            ],
            resources: [.process("Presentation/Setup/SetupSwarm.metal")]
        ),

        // Board — core-контекст главного экрана: доска change'ей и каркас окна
        // (рейл · сайдбар · канвас · инспектор по требованию). Домена у него
        // пока НЕТ вовсе: экран принят эталоном (design/candidates/main-screen-board.md)
        // раньше, чем появились сущности, и весь мир берёт из фикстур
        // презентационного слоя — они для того и лежат отдельным каталогом
        // `Presentation/Fixture`, чтобы умереть целиком, когда придёт `Change`.
        .target(name: "Board", dependencies: ["Core"]),

        // Run — core-контекст: запуск агент-сессии и лента транскрипта. Читает
        // настройки через публичный контракт Setting; общее берёт из Core.
        .target(
            name: "Run",
            dependencies: [
                "Core",
                "Setting",
                .product(name: "Subprocess", package: "swift-subprocess"),
                // Адаптеры запуска сессии помечены @Component (маркер) — им нужен только SparkIoC.
                .product(name: "SparkIoC", package: "spark"),
            ]
        ),

        // Bootstrap — bootstrap приложения (наш аналог Spring Boot).
        // Единственный, кто видит все контексты сразу: собирает контекст из бинов и
        // сшивает их корневые виды (гейт мастера настроек поверх консоли Run), а
        // заодно держит хром окна (`WindowConfigurator`) — про окно приложения знает
        // корень композиции, а не контекст.
        .target(
            name: "Bootstrap",
            dependencies: [
                "Core",
                "Setting",
                "Run",
                "Board",
                // Контекст/Environment живут в SparkIoC; bootstrap собирает контейнер.
                .product(name: "SparkIoC", package: "spark"),
            ],
            // Реестр бинов не пишем руками: плагин Spark просканит @Component всех таргетов пакета
            // на этапе сборки и сгенерит BeanScan сюда, в корень композиции. Аналог @ComponentScan.
            plugins: [.plugin(name: "ComponentScanPlugin", package: "spark")]
        ),

        .executableTarget(name: "OrbBench", dependencies: ["Core"]),

        // Тесты — по контексту.
        .testTarget(
            name: "SettingTests",
            dependencies: [
                "Setting",
                // Core — и ради тактического ядра домена, и ради теста-паритета физики роёв:
                // он сверяет внутренности роя мастера настройки (презентация Setting) и орб-лоадера
                // (Core) разом, через @testable обоих.
                "Core",
                // Тест сборки контейнера: резолв бинов из SettingConfiguration + Environment.
                .product(name: "SparkIoC", package: "spark"),
            ]
        ),
        // Реальный граф приложения (BeanScan.definitions + SettingConfiguration().definitions)
        // собирается и резолвится. Сам контейнер тестируется у себя, в Spark; здесь — наш граф.
        .testTarget(
            name: "BootstrapTests",
            dependencies: [
                "Bootstrap", "Run", "Setting", .product(name: "SparkIoC", package: "spark"),
            ]
        ),
        .testTarget(name: "RunTests", dependencies: ["Run", "Setting"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
