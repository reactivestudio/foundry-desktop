import AppKit
import Core
import CoreGraphics
import SwiftUI

/// Онбординговые константы стиля — то, чего нет в `DesignTokens.swift`, но что
/// принято в макете (docs/design/mockups/onboarding.html): производные OKLCH
/// цвета кнопки, ступени янтарной плашки, парящая тень карточек, кегль hero.
///
/// Значения кнопки/янтаря посчитаны из OKLCH единожды и зашиты как sRGB —
/// SwiftUI не смешивает в OKLCH, а опорные точки макета фиксированы.
enum OB {
    // backdrop — самый нижний слой окна установки (#0E0B14, почти чёрный с чуть
    // фиолетовым тоном). Только фон окна; поверхности карточек/панелей — bg (ниже).
    static let backdrop = Color(hexValue: 0x0E0B14)
    // bg — тёмная поверхность карточек/панелей и их подложек (bg.base #05030D)
    static let bg = Token.Background.base

    // primary-кнопка: плоский ультрамарин; hover/pressed — вглубь и в пурпур
    static let ultramarine = Token.Brand.ultramarine  // #2F5CFF
    static let ultraHover = Color(hexValue: 0x4E44F1)  // oklch l-0.035 h+10
    static let ultraPressed = Color(hexValue: 0x4330DF)  // oklch l-0.085 h+10

    // янтарная плашка лейбла «AI» — градиент по OKLCH
    static let amberTop = Color(hexValue: 0xFFBB34)  // l+0.035
    static let amberMid = Token.Brand.amber  // #FFB020
    static let amberBottom = Color(hexValue: 0xFBA21B)  // l-0.03 h-6

    /// Цвета текста онбординга. Вложенный namespace вместо t-префикса —
    /// читается `OB.Text.primary`. `Token.Text` (глобальный) остаётся доступен
    /// по полному имени.
    enum Text {
        static let primary = Color(white: 1, opacity: 0.96)
        static let secondary = Token.Text.secondary  // 0.70
        static let tertiary = Token.Text.tertiary  // 0.50
    }

    static let success = Token.Semantic.success  // #4ADE80

    // нейтральная плашка карточек/панелей: свет сверху вниз
    static let cardFillTop = Color(white: 1, opacity: 0.07)
    static let cardFillBottom = Color(white: 1, opacity: 0.03)

    // движение: делегируем в общий AppMotion (единый источник законов движения на
    // всё приложение). Здесь — лишь онбординговые алиасы, чтобы не трогать call-sites.
    /// «Настоящая» кривая макета cubic-bezier(0.2,0,0,1). См. `AppMotion.ease`.
    static func easeReal(_ duration: Double) -> Animation { AppMotion.ease(duration) }
    /// ЗАКОН ховера (быстро на входе, заметно медленнее на уходе) — общий на всё
    /// приложение. См. `AppMotion.hover`. Вешать как `.animation(OB.hoverAnim(h), value: h)`.
    static func hoverAnim(_ hovering: Bool) -> Animation { AppMotion.hover(hovering) }

    /// Угол карточек агентов/расширений и панелей `.setpanel` — общий на клип,
    /// микрорельеф кромки, рамку выбора и регистрацию парящей тени. Один на все,
    /// чтобы форма поверхностей мастера не расходилась по вью.
    static let cardRadius: CGFloat = 22

    // squircle-угол — истинный гиперэллипс (см. Squircle), не приближение .continuous
    static func squircle(_ r: CGFloat) -> Squircle { Squircle(cornerRadius: r) }
}

/// Истинный гиперэллипс — то, что CSS зовёт `corner-shape: squircle` = superellipse(2) =
/// показатель n=4: |x|⁴+|y|⁴=1. `RoundedRectangle(.continuous)` — лишь приближение Apple
/// (заметно круглее по бокам); здесь угол строится ровно по кривой макета. Экспонента
/// параметризации 2/n = 0.5: точка четвертинки = (cos t)^0.5, (sin t)^0.5.
struct Squircle: InsettableShape {
    var cornerRadius: CGFloat
    /// Показатель суперэллипса |x|ⁿ+|y|ⁿ=1. Канон системы — 4 (CSS `corner-shape:
    /// squircle`). Меньше — угол ближе к дуге окружности и читается круглее (n=2 —
    /// ровно окружность); больше — угол площе, ближе к прямому.
    var exponent: CGFloat = 4
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let rad = max(0, min(cornerRadius - insetAmount, min(r.width, r.height) / 2))
        guard rad > 0 else { return Path(r) }
        let x0 = r.minX
        let y0 = r.minY
        let x1 = r.maxX
        let y1 = r.maxY
        let seg = 16
        let e = 2 / exponent  // экспонента параметризации: n=4 → 0.5, n=2 → 1 (окружность)
        func se(_ i: Int) -> (CGFloat, CGFloat) {
            let t = (.pi / 2) * CGFloat(i) / CGFloat(seg)
            return (pow(cos(t), e), pow(sin(t), e))
        }
        var p = Path()
        p.move(to: CGPoint(x: x0 + rad, y: y0))
        p.addLine(to: CGPoint(x: x1 - rad, y: y0))
        for i in 0...seg {
            let (c, s) = se(i)  // верх-право
            p.addLine(to: CGPoint(x: x1 - rad + rad * s, y: y0 + rad - rad * c))
        }
        p.addLine(to: CGPoint(x: x1, y: y1 - rad))
        for i in 0...seg {
            let (c, s) = se(i)  // низ-право
            p.addLine(to: CGPoint(x: x1 - rad + rad * c, y: y1 - rad + rad * s))
        }
        p.addLine(to: CGPoint(x: x0 + rad, y: y1))
        for i in 0...seg {
            let (c, s) = se(i)  // низ-лево
            p.addLine(to: CGPoint(x: x0 + rad - rad * s, y: y1 - rad + rad * c))
        }
        p.addLine(to: CGPoint(x: x0, y: y0 + rad))
        for i in 0...seg {
            let (c, s) = se(i)  // верх-лево
            p.addLine(to: CGPoint(x: x0 + rad - rad * c, y: y0 + rad - rad * s))
        }
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Squircle {
        var s = self
        s.insetAmount += amount
        return s
    }
}

/// Микрорельеф кромок (канон 09): на bg.base поверхность отделяет СВЕТ по кромке,
/// не тёмная тень — еле заметный блик сверху (0.05) и лёгкая подрезка снизу.
private struct EdgeRelief: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay(
            OB.squircle(radius).strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), .clear, .clear, Color.black.opacity(0.14)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        )
    }
}

extension View {
    func edgeRelief(_ radius: CGFloat) -> some View { modifier(EdgeRelief(radius: radius)) }
    /// Курсор-рука на кликабельном. В макете (веб) у всего кликабельного
    /// `cursor: pointer`; в нативе по умолчанию курсор не меняется — вешаем
    /// системный link-указатель. Работает на КЛЮЧЕВОМ окне; на неактивном окне
    /// macOS свой курсор показывать почти не даёт — по договорённости не боремся.
    func clickCursor() -> some View { pointerStyle(.link) }
}
