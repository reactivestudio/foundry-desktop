import Foundation
import SwiftContextAot

// Кодоген BeanScan для bootstrap'а. Аргументы: <путь-вывода> [<Модуль> <путь-к-файлу> ...].
// Дискаверинг (какие файлы каких модулей сканить) сделал плагин — у него доступ к графу
// пакета; здесь только «прочитать → scan → generate → записать». Вся логика (замыкание
// супертипов, дженерики, импорты) — в SwiftContextAot, оттуда же юнит-тесты. Файл кладётся в
// plugin-work-каталог (.build), в Sources не попадает — линтер/форматтер его не трогают.

let arguments = Array(CommandLine.arguments.dropFirst())

guard let outputPath = arguments.first else {
    FileHandle.standardError.write(Data("SwiftContextAotProcessor: не задан путь вывода\n".utf8))
    exit(1)
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
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
    sources.append((module: module, text: contents))
}

let scanner = ClassPathBeanDefinitionScanner()
let beans = scanner.scan(sources: sources)
let generated = BeanRegistrationsCodeGenerator()
    .generateCode(for: beans, typeModules: scanner.moduleForType) + "\n"

do {
    try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)
} catch {
    let message = "SwiftContextAotProcessor: не записал \(outputPath): \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
