// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FoundryKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Presentation", targets: ["Presentation"]),
        // Configuration — корень сборки зависимостей (Swinject-контейнер). Это тот
        // продукт, что линкует приложение: он один знает конкретные детали.
        .library(name: "Configuration", targets: ["Configuration"]),
        // Infrastructure — реализации портов Domain/Application (детали).
        // Вендор-адаптеры (Claude и др.), хранилища, файловые репозитории.
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
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
        // Domain — ядро: сущности, VO, доменные события, порты. Импортирует только Foundation.
        .target(name: "Domain"),
        // Application — use-cases (оркестрация) + граница транзакционности. Импортирует Domain.
        .target(name: "Application", dependencies: ["Domain"]),
        // Infrastructure — реализации портов. Импортирует Domain (при нужде Application).
        .target(
            name: "Infrastructure",
            dependencies: [
                "Domain",
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        // Presentation — views, тонкие сторы, DesignSystem/Orb/Onboarding. Импортирует Domain, Application.
        .target(
            name: "Presentation",
            dependencies: ["Domain", "Application"],
            resources: [
                .process("Orb/OrbSwarm.metal"),
                .process("Onboarding/OnboardingSwarm.metal"),
            ]
        ),
        // Configuration — Swinject Assembly + bootstrap. Импортирует всё.
        .target(
            name: "Configuration",
            dependencies: [
                "Domain",
                "Application",
                "Infrastructure",
                "Presentation",
                .product(name: "Swinject", package: "Swinject"),
            ]
        ),
        .executableTarget(name: "OrbBench", dependencies: ["Presentation"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "InfrastructureTests", dependencies: ["Infrastructure"]),
        .testTarget(name: "PresentationTests", dependencies: ["Presentation"]),
    ]
)
