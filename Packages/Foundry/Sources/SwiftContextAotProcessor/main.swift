import Foundation
import SwiftContextAot

// Кодоген BeanScan для bootstrap'а. Аргументы: <путь-вывода> [<Модуль> <путь-к-файлу> ...].
// Дискаверинг (какие файлы каких модулей сканить) сделал плагин — у него доступ к графу
// пакета; здесь только «прочитать → scan → generate → записать». Вся логика (замыкание
// супертипов, дженерики, импорты) — в SwiftContextAot, оттуда же юнит-тесты. Файл кладётся в
// plugin-work-каталог (.build), в Sources не попадает — линтер/форматтер его не трогают.

let arguments = Array(CommandLine.arguments.dropFirst())

/// Сказать в stderr и уронить сборку. Тихо продолжать нельзя: пропущенный исходник или незамеченная
/// проблема скана превращаются в отсутствующий бин и `noSuchBeanDefinition` в другом конце графа.
func fail(reason: String) -> Never {
    FileHandle.standardError.write(Data("SwiftContextAotProcessor: \(reason)\n".utf8))
    exit(1)
}

guard let outputPath = arguments.first else {
    fail(reason: "не задан путь вывода")
}

// Дальше — пары «Модуль» «путь-к-.swift». Идём по две. Транзитивное замыкание супертипов
// требует ГЛОБАЛЬНОГО прохода: сперва собираем ВСЕ исходники, потом сканируем разом.
let pairs = Array(arguments.dropFirst())
var sources: [(module: String, text: String)] = []
var index = 0
while index + 1 < pairs.count {
    let module = pairs[index]
    let path = pairs[index + 1]
    index += 2
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail(reason: "не прочитал исходник \(path) — скан был бы неполным, бины из этого файла пропали бы молча")
    }
    sources.append((module: module, text: contents))
}

let scanner = ClassPathBeanDefinitionScanner()
let beans = scanner.scan(sources: sources)

// Диагностика скана — ошибки СБОРКИ: аннотация, которая не станет бином, обязана быть видна здесь,
// а не всплыть на старте приложения отсутствующим бином.
if !scanner.problems.isEmpty {
    for problem in scanner.problems {
        FileHandle.standardError.write(Data("SwiftContextAotProcessor: \(problem.message)\n".utf8))
    }
    fail(reason: "проблем скана: \(scanner.problems.count) — BeanScan не сгенерирован")
}

let generated = BeanRegistrationsAotContribution().generateCode(
    for: beans,
    configurations: scanner.configurations,
    typeModules: scanner.moduleForType
) + "\n"

do {
    try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)
} catch {
    fail(reason: "не записал \(outputPath): \(error)")
}
