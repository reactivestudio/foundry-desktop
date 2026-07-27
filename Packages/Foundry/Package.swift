// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Foundry",
    platforms: [.macOS(.v15)],
    products: [
        // Configuration — корень композиции (Swinject-контейнер + корневой вид). Это
        // единственный продукт, что линкует приложение: он один знает конкретные
        // детали и сшивает контексты между собой.
        .library(name: "Configuration", targets: ["Configuration"]),
        // Замер роя на настоящей Metal-железке: swift run OrbBench
        .executable(name: "OrbBench", targets: ["OrbBench"]),
    ],
    dependencies: [
        // Пре-1.0 — пиновать версию (practices 06, пункт 1.1).
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "0.5.0"),
        // DI-контейнер: регистрация/резолв по интерфейсу (Spring-бины в Swift).
        .package(url: "https://github.com/Swinject/Swinject", from: "2.9.1"),
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
        .target(name: "Setting"),

        // Run — core-контекст: запуск агент-сессии и лента транскрипта. Читает
        // настройки через публичный контракт Setting; общее берёт из Core.
        .target(
            name: "Run",
            dependencies: [
                "Core",
                "Setting",
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),

        // Onboarding — контекст первого запуска (Metal-имитация мастера). Чистая
        // презентация; общее (движение, рой, лог) — из Core. Не знает Run/Setting.
        .target(
            name: "Onboarding",
            dependencies: ["Core"],
            resources: [.process("Presentation/OnboardingSwarm.metal")]
        ),

        // Configuration — корень композиции (наш аналог Spring @Configuration).
        // Единственный, кто видит все контексты сразу: связывает порты с
        // реализациями (Swinject) и сшивает корневые виды контекстов (гейт
        // онбординга поверх консоли).
        .target(
            name: "Configuration",
            dependencies: [
                "Core",
                "Setting",
                "Run",
                "Onboarding",
                .product(name: "Swinject", package: "Swinject"),
            ]
        ),

        .executableTarget(name: "OrbBench", dependencies: ["Core"]),

        // Тесты — по контексту.
        .testTarget(name: "RunTests", dependencies: ["Run", "Setting"]),
        .testTarget(name: "SettingTests", dependencies: ["Setting"]),
        // Core в зависимостях — ради теста-паритета физики роёв, что сверяет
        // внутренности Onboarding и Core разом (@testable обоих).
        .testTarget(name: "OnboardingTests", dependencies: ["Onboarding", "Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
