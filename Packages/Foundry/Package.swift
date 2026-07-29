// swift-tools-version: 6.1
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Foundry",
    platforms: [.macOS(.v15)],
    products: [
        // Bootstrap — bootstrap приложения (SwiftContext-контейнер + корневой вид). Это
        // единственный продукт, что линкует приложение: он один знает конкретные
        // детали и сшивает контексты между собой.
        .library(name: "Bootstrap", targets: ["Bootstrap"]),
        // Замер роя на настоящей Metal-железке: swift run OrbBench
        .executable(name: "OrbBench", targets: ["OrbBench"]),
    ],
    dependencies: [
        // Пре-1.0 — пиновать версию (practices 06, пункт 1.1).
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "0.5.0"),
        // SwiftSyntax — на нём стоят макросы-маркеры (@Component/@Bean/@Configuration) и скан-движок.
        .package(url: "https://github.com/swiftlang/swift-syntax", "600.0.0"..<"602.0.0"),
    ],
    targets: [
        // Верхний уровень модульности — bounded context (фича), а не технический
        // слой. Внутри каждого контекста слои DDD живут папками
        // (Domain/Application/Infrastructure/Presentation); граница КОНТЕКСТА
        // (фича↔фича) сторожится компилятором через таргеты, граница слоёв внутри —
        // дисциплина контекста. Растёт число контекстов — растёт число таргетов
        // линейно; разжиревший контекст повышается до пофичевых под-таргетов.

        // SwiftContextMacros — реализация макросов (@Component). Компилятор гоняет её как
        // плагин на этапе сборки; тут живёт кодоген через SwiftSyntax.
        .macro(
            name: "SwiftContextMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // SwiftContext — DI-ядро (Spring-верный, вместо Swinject): маркеры-макросы
        // (@Component/@Bean/@Configuration) + Scope + контейнер (DefaultListableBeanFactory /
        // AnnotationConfigApplicationContext) + Environment. Ниже контекстов, но НЕ в Core (Core про
        // DI не знает). Пакет самодостаточен — задел на вынос в отдельную либу.
        .target(
            name: "SwiftContext",
            dependencies: ["SwiftContextMacros"]
        ),

        // SwiftContextAot — движок «classpath-scan»: парсит исходники на атрибут @Component
        // (SwiftSyntax), строит граф наследования и генерит BeanScan (определения бинов как данные),
        // считая targetTypes = транзитивное замыкание супертипов. Чистые типы (scan/generate) —
        // отсюда и юнит-тесты; плагин лишь скормит ему файлы.
        .target(
            name: "SwiftContextAot",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),

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
                // SwiftContext; сборку по ним делает скан-плагин, самому контексту хватает SwiftContext.
                "SwiftContext",
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
                // Адаптеры запуска сессии помечены @Component (маркер) — им нужен только SwiftContext.
                "SwiftContext",
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
                // Контекст/Environment живут в SwiftContext; bootstrap собирает контейнер.
                "SwiftContext",
            ],
            // Реестр бинов не пишем руками: плагин просканит @Component на этапе сборки.
            plugins: ["ComponentScanPlugin"]
        ),

        .executableTarget(name: "OrbBench", dependencies: ["Core"]),

        // Кодоген-исполняемый: гоняет SwiftContextAot по скормленным плагином исходникам и
        // пишет BeanScan (определения бинов как данные). Дискаверинг файлов — за плагином (граф пакета).
        .executableTarget(name: "SwiftContextAotProcessor", dependencies: ["SwiftContextAot"]),

        // Build-плагин: скармливает генератору исходники всех контекстов, тот ищет
        // @Component и генерит BeanScan для bootstrap'а. Аналог @ComponentScan Spring, но
        // на компиляции — безопасной рантайм-рефлексии по типам в Swift нет.
        .plugin(
            name: "ComponentScanPlugin",
            capability: .buildTool(),
            dependencies: ["SwiftContextAotProcessor"]
        ),

        // Тесты — по контексту.
        .testTarget(
            name: "SettingTests",
            dependencies: [
                "Setting",
                "Core",
                // Тест сборки контейнера: резолв бинов из SettingConfiguration + Environment.
                "SwiftContext",
            ]
        ),
        // Тесты DI-ядра: @Configuration → definitions() через SwiftContext + Environment/Scope.
        .testTarget(
            name: "SwiftContextTests",
            dependencies: ["SwiftContext"]
        ),
        .testTarget(name: "SwiftContextAotTests", dependencies: ["SwiftContextAot"]),
        // Доказательство нового пути: реальный граф приложения (BeanScan.definitions +
        // SettingConfiguration().definitions) собирается и резолвится через SwiftContext.
        .testTarget(
            name: "BootstrapTests",
            dependencies: ["Bootstrap", "SwiftContext", "Run", "Setting"]
        ),
        .testTarget(name: "RunTests", dependencies: ["Run", "Setting"]),
        // Core в зависимостях — ради теста-паритета физики роёв, что сверяет
        // внутренности Onboarding и Core разом (@testable обоих).
        .testTarget(name: "OnboardingTests", dependencies: ["Onboarding", "Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
