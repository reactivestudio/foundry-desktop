import Foundation
import PackagePlugin

/// Build-плагин: на стадии сборки скармливает исходники всех библиотечных контекстов
/// генератору `SwiftContextAotProcessor` (тот через `SwiftContextAot` ищет `@Component` и генерит
/// `BeanScan`). Наш аналог `@ComponentScan`: безопасной рантайм-рефлексии по типам в Swift нет
/// (структуры невидимы ObjC-рантайму, скан секций метаданных ломает dead-code stripping), поэтому
/// дискаверинг на компиляции. Истинный OCP: новый `@Component`-адаптер попадает в контейнер без
/// правок реестра в bootstrap.
///
/// Берём только библиотечные таргеты (`.generic`): тесты и исполняемые исключены, чтобы
/// тестовые `@Component`-типы (приватные, из bootstrap не видны) не утекли в реестр.
@main
struct ComponentScanPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        var inputs: [URL] = []
        var arguments: [String] = []

        let libraries = context.package.targets
            .compactMap { $0 as? SwiftSourceModuleTarget }
            .filter { $0.kind == .generic }
        for module in libraries {
            for file in module.sourceFiles where file.url.pathExtension == "swift" {
                inputs.append(file.url)
                arguments.append(module.name)
                arguments.append(file.url.path)
            }
        }

        let output = context.pluginWorkDirectoryURL.appending(path: "BeanScan.generated.swift")
        let generator = try context.tool(named: "SwiftContextAotProcessor")

        return [
            .buildCommand(
                displayName: "BeanScan classpath-scan (@Component → BeanScan)",
                executable: generator.url,
                arguments: [output.path] + arguments,
                inputFiles: inputs,
                outputFiles: [output]
            ),
        ]
    }
}
