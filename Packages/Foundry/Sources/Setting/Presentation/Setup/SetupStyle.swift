import AppKit
import Core
import CoreGraphics
import SwiftUI

/// Константы стиля мастера настройки — то, чего нет в `DesignTokens.swift`, но что
/// принято в макете (docs/design/mockups/setup.html): производные OKLCH
/// цвета кнопки, ступени янтарной плашки, парящая тень карточек, кегль hero.
///
/// Значения кнопки/янтаря посчитаны из OKLCH единожды и зашиты как sRGB —
/// SwiftUI не смешивает в OKLCH, а опорные точки макета фиксированы.
enum SetupStyle {
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

    /// Цвета текста мастера настройки. Вложенный namespace вместо t-префикса —
    /// читается `SetupStyle.Text.primary`. `Token.Text` (глобальный) остаётся доступен
    /// по полному имени.
    enum Text {
        static let primary = Token.Text.primary  // 0.96
        static let secondary = Token.Text.secondary  // 0.70
        static let tertiary = Token.Text.tertiary  // 0.50
    }

    static let success = Token.Semantic.success  // #4ADE80

    // нейтральная плашка карточек/панелей: свет сверху вниз
    static let cardFillTop = Color(white: 1, opacity: 0.07)
    static let cardFillBottom = Color(white: 1, opacity: 0.03)

    // движение: делегируем в общий AppMotion (единый источник законов движения на
    // всё приложение). Здесь — лишь алиасы мастера настройки, чтобы не трогать call-sites.
    /// «Настоящая» кривая макета cubic-bezier(0.2,0,0,1). См. `AppMotion.ease`.
    static func easeReal(_ duration: Double) -> Animation { AppMotion.ease(duration) }
    /// ЗАКОН ховера (быстро на входе, заметно медленнее на уходе) — общий на всё
    /// приложение. См. `AppMotion.hover`. Вешать как `.animation(SetupStyle.hoverAnim(h), value: h)`.
    static func hoverAnim(_ hovering: Bool) -> Animation { AppMotion.hover(hovering) }

    /// Угол карточек агентов/расширений и панелей `.setpanel` — общий на клип,
    /// микрорельеф кромки, рамку выбора и регистрацию парящей тени. Один на все,
    /// чтобы форма поверхностей мастера не расходилась по вью.
    static let cardRadius: CGFloat = 22

    // squircle-угол — истинный гиперэллипс (см. Squircle), не приближение .continuous
    static func squircle(_ r: CGFloat) -> Squircle { Squircle(cornerRadius: r) }
}
