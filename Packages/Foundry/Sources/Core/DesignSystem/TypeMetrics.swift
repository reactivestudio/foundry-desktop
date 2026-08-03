import AppKit
import SwiftUI

/**
 Высота строки токена — СНЯТАЯ, а не вычисленная.

 Это единственное число во всей системе, которое нельзя вывести. Кегль 13
 занимает 16, кегль 11 — 14, а кегль 16 — 19, и ни одна арифметика по
 метрикам шрифта (ни `ascender − descender`, ни округление вверх каждой
 из частей, ни `NSLayoutManager.defaultLineHeight`) не даёт этот ряд целиком:
 сходится на мелких кеглях и врёт на крупных. Правило доски здесь буквально:
 рукописному числу рядом с вычислимым не верить, а СВЕРЯТЬ, — а если
 вычислить нечем, то мерить.

 Мерка — `NSAttributedString.size()` тем же шрифтом: она совпала со SwiftUI
 на всех одиннадцати токенах системы и на обоих семействах. Она дешевле
 промежуточного `NSHostingView` и, главное, не трогает вёрстку изнутри
 вёрстки. Замер кладётся в кэш по кеглю, весу и семейству: разных сочетаний
 в приложении полтора десятка.

 Интерлиньяж меньше снятой высоты недостижим: `lineSpacing` умеет только
 разводить строки, а сдвинуть их ближе — нет. Такой токен один — `label`
 (11/13, а строка 14), и он набирается на пункт выше канона.
 */
@MainActor
public enum TypeMetrics {
    /// Сколько занимает одна строка этого токена на экране.
    public static func lineHeight(of token: TypeToken) -> CGFloat {
        let weight = nsWeight(token.weight)
        let key = Key(size: token.size, weight: weight.rawValue, isMono: token.family == .mono)
        if let known = measured[key] { return known }
        let font =
            key.isMono
            ? NSFont.monospacedSystemFont(ofSize: token.size, weight: weight)
            : NSFont.systemFont(ofSize: token.size, weight: weight)
        // Строка из букв с выносными элементами вверх и вниз: высота строки
        // от них не зависит, но пусть меряется на настоящем тексте.
        let height = NSAttributedString(string: "Ля", attributes: [.font: font]).size().height
        measured[key] = height
        return height
    }

    /// Насколько развести строки, чтобы шаг вышел интерлиньяжем канона.
    public static func spacing(of token: TypeToken) -> CGFloat {
        max(0, token.leading - lineHeight(of: token))
    }

    /// Полулидинг: столько недостаёт коробке сверху и снизу, чтобы текст из N
    /// строк был ровно N × интерлиньяж при ЛЮБОМ N. В вёрстке с интерлиньяжем
    /// недостающее делится поровну над первой строкой и под последней —
    /// здесь то же самое, полем.
    public static func halfLeading(of token: TypeToken) -> CGFloat {
        spacing(of: token) / 2
    }

    private struct Key: Hashable {
        let size: CGFloat
        let weight: CGFloat
        let isMono: Bool
    }

    private static var measured: [Key: CGFloat] = [:]

    /// Вес токена в терминах AppKit: шрифт для замера спрашивается у него.
    private static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        case .light: .light
        default: .regular
        }
    }
}
