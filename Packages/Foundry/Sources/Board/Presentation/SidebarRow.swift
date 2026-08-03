import Foundation

/**
 Строка сайдбара — и в срезе, и в списке проектов: объект один, пульт один.

 У «Всё в работе» числа нет намеренно. Это состояние «фильтр снят», а не
 четвёртое число: его значение и так лежит суммой трёх строк ниже, а одно
 число обязано жить в одном месте.
 */
struct SidebarRow: Identifiable, Sendable {
    let id = UUID()
    let title: String
    /// nil — числа у строки нет; строка «—» — число неизвестно (нет связи).
    let countText: String?

    init(_ title: String, _ countText: String? = nil) {
        self.title = title
        self.countText = countText
    }

    /// Тысячи — тонкой шпацией: 1 247, а не 1247 и не 1,247.
    static func number(_ value: Int) -> String {
        let digits = Array(String(value))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append("\u{2009}") }
            out.append(digit)
        }
        return out
    }
}
