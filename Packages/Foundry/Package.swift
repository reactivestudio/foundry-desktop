// swift-tools-version: 6.1
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
        .package(url: "https://github.com/reactivestudio/spark", exact: "0.1.0"),
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
            resources: [.process("DesignSystem/OrbSwarm.metal")]
        ),

        // Setting — supporting-субдомен пользовательских настроек (имя в
        // единственном числе). Внутри — отдельные сущности: сегодня реальна одна,
        // `Tool` (настройки агента и foundry cli), полным срезом слоёв (сущность +
        // порт + сценарий + адаптер UserDefaults). Целевой состав сущностей —
        // Profile, Notification, Tool, Appearance, Access, General: каждая
        // добавляется своим файлом-срезом (Domain/<E>.swift + Application/<E>Service
        // + Infrastructure/UserDefaults<E>Repository), когда у неё появляется
        // реальное поле. Пустышек наперёд не заводим. Ни от кого не зависит, кроме
        // системы.
        .target(
            name: "Setting",
            dependencies: [
                "Core",
                // Вся DI-поверхность контекста (@Component/@Configuration/@Bean) — маркеры из
                // Spark; сборку по ним делает скан-плагин, самому контексту хватает SparkIoC.
                .product(name: "SparkIoC", package: "spark"),
            ]
        ),

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

        // Onboarding — контекст первого запуска (Metal-имитация мастера). Чистая
        // презентация; общее (движение, рой, лог) — из Core. Не знает Run/Setting.
        .target(
            name: "Onboarding",
            dependencies: ["Core"],
            resources: [.process("Presentation/OnboardingSwarm.metal")]
        ),

        // Bootstrap — bootstrap приложения (наш аналог Spring Boot).
        // Единственный, кто видит все контексты сразу: собирает контекст из бинов и
        // сшивает корневые виды контекстов (гейт онбординга поверх консоли).
        .target(
            name: "Bootstrap",
            dependencies: [
                "Core",
                "Setting",
                "Run",
                "Onboarding",
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
        // Core в зависимостях — ради теста-паритета физики роёв, что сверяет
        // внутренности Onboarding и Core разом (@testable обоих).
        .testTarget(name: "OnboardingTests", dependencies: ["Onboarding", "Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
