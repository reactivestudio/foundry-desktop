import SwiftUI

/**
 Набор текста типографским токеном целиком: кегль, вес, семейство, трекинг,
 интерлиньяж и полулидинг разом.

 Полулидинг — то, чего в SwiftUI нет вовсе и о чём проще всего забыть.
 `lineSpacing` разводит строки МЕЖДУ собой, но коробка текста остаётся высотой
 в свои строки: однострочный заголовок при интерлиньяже 18 занимает 16, и всё,
 что стоит под ним, поднимается на два пункта. В вёрстке с интерлиньяжем
 (CSS, макеты канона) недостающее делится поровну над первой строкой и под
 последней — здесь то же самое, полем.

 После него коробка из N строк ровно N × leading при любом N — и карточка
 в одну строку становится ровно на 18 выше пустой, как обещает канон.
 Обе величины СНЯТЫ у текста, а не выведены из кегля: смотри `TypeMetrics`.
 */
public struct TypographyModifier: ViewModifier {
    private let token: TypeToken

    public init(_ token: TypeToken) {
        self.token = token
    }

    public func body(content: Content) -> some View {
        content
            .font(token.font)
            .tracking(token.tracking * token.size)
            .textCase(token.isUppercased ? .uppercase : nil)
            .lineSpacing(TypeMetrics.spacing(of: token))
            .padding(.vertical, TypeMetrics.halfLeading(of: token))
    }
}

extension View {
    /// Набрать текст токеном канона. Кегли и интерлиньяжи руками не писать:
    /// нет нужного токена — сначала завести его в `design/tokens/tokens.json`.
    public func typography(_ token: TypeToken) -> some View {
        modifier(TypographyModifier(token))
    }
}
