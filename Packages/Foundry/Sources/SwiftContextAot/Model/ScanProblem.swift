/// Проблема, найденная сканом: то, что выглядит как рабочая аннотация, но бином не станет (или
/// станет неоднозначным). Собираем СПИСКОМ, а не бросаем на первой: автору полезно увидеть все
/// огрехи проводки за один прогон сборки. Аналог того, что Spring делает исключением при
/// сканировании (`BeanDefinitionStoreException`), только у нас это стадия компиляции — потому
/// диагностика, а не throw: процессор печатает всё в stderr и роняет сборку.
///
/// Главное правило, ради которого этот тип есть: скан НЕ МОЛЧИТ. Молча пропущенная аннотация даёт
/// `noSuchBeanDefinition` в другом конце графа, где причину уже не видно.
public struct ScanProblem: Equatable, Sendable {
    /// Модуль, где объявлен виновник.
    public let module: String
    /// Тип-виновник (или имя бина, если проблема про имя).
    public let subject: String
    /// Что именно не так — текстом, в котором видно, что делать.
    public let reason: String

    public init(module: String, subject: String, reason: String) {
        self.module = module
        self.subject = subject
        self.reason = reason
    }

    /// Строка для stderr: `Модуль.Тип: причина`.
    public var message: String {
        "\(module).\(subject): \(reason)"
    }
}
