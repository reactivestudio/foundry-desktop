import Foundation

/**
 Строковые хелперы общего словаря. `trimmed()` — нормализация без ведущих/хвостовых
 пробелов и переводов строк; выделена в Core, чтобы каждый контекст не повторял
 `trimmingCharacters(in:)` и не тащил из-за одной строки `import Foundation`. Метод (а
 не свойство) — по прецеденту stdlib: «вернуть изменённую копию» — это `sorted()`,
 `uppercased()`, `trimmingCharacters(in:)`, то есть метод с суффиксом -ed.
 */
public extension String {
    /// Строка без ведущих и хвостовых пробелов и переводов строк.
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
