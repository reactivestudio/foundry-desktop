import SwiftUI

/// Онбординговые константы стиля — то, чего нет в `DesignTokens.swift`, но что
/// принято в макете (docs/design/mockups/onboarding.html): производные OKLCH
/// цвета кнопки, ступени янтарной плашки, парящая тень карточек, кегль hero.
///
/// Значения кнопки/янтаря посчитаны из OKLCH единожды и зашиты как sRGB —
/// SwiftUI не смешивает в OKLCH, а опорные точки макета фиксированы.
enum OB {
    // фон окна установки — bg.base #05030D
    static let bg = Token.Background.base

    // primary-кнопка: плоский ультрамарин; hover/pressed — вглубь и в пурпур
    static let ultramarine = Token.Brand.ultramarine  // #2F5CFF
    static let ultraHover = Color(hexValue: 0x4E44F1)  // oklch l-0.035 h+10
    static let ultraPressed = Color(hexValue: 0x4330DF)  // oklch l-0.085 h+10

    // янтарная плашка лейбла «AI» — градиент по OKLCH
    static let amberTop = Color(hexValue: 0xFFBB34)  // l+0.035
    static let amberMid = Token.Brand.amber  // #FFB020
    static let amberBottom = Color(hexValue: 0xFBA21B)  // l-0.03 h-6

    // текст
    static let tPrimary = Color(white: 1, opacity: 0.96)
    static let tSecondary = Token.Text.secondary  // 0.70
    static let tTertiary = Token.Text.tertiary  // 0.50
    static let tDisabled = Token.Text.disabled  // 0.38
    static let tAccent = Token.Text.accent  // #7C9AFF

    static let success = Token.Semantic.success  // #4ADE80

    // нейтральная плашка карточек/панелей: свет сверху вниз
    static let cardFillTop = Color(white: 1, opacity: 0.07)
    static let cardFillBottom = Color(white: 1, opacity: 0.03)

    static let borderSubtle = Token.Border.subtle  // 0.08
    static let borderDefault = Token.Border.default  // 0.12

    // движение: «настоящая» кривая макета cubic-bezier(0.2,0,0,1)
    static func easeReal(_ d: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: d) }
    static let mFast = 0.15
    static let mBase = 0.22

    // squircle-угол — истинный гиперэллипс (см. Squircle), не приближение .continuous
    static func squircle(_ r: CGFloat) -> Squircle { Squircle(cornerRadius: r) }
}

/// Истинный гиперэллипс — то, что CSS зовёт `corner-shape: squircle` = superellipse(2) =
/// показатель n=4: |x|⁴+|y|⁴=1. `RoundedRectangle(.continuous)` — лишь приближение Apple
/// (заметно круглее по бокам); здесь угол строится ровно по кривой макета. Экспонента
/// параметризации 2/n = 0.5: точка четвертинки = (cos t)^0.5, (sin t)^0.5.
struct Squircle: InsettableShape {
    var cornerRadius: CGFloat
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
        func se(_ i: Int) -> (CGFloat, CGFloat) {
            let t = (.pi / 2) * CGFloat(i) / CGFloat(seg)
            return (pow(cos(t), 0.5), pow(sin(t), 0.5))
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

/// Парящая тень карточек и панелей мастера (--shadow-float): тёмное гало над
/// роем. На голом bg.base невидима (нечего гасить) — работает лишь в полосе, где
/// сзади яркий рой; глубину дублирует микрорельеф кромок. В SwiftUI радиус ≈
/// блюр/2, слои сгущены к ядру. Живёт на непрозрачной bg.base-подложке под телом,
/// чтобы рой не просвечивал и тень не темнила соседей.
private struct FloatShadow: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(
                OB.squircle(radius).fill(OB.bg)
                    .shadow(color: .black.opacity(0.80), radius: 48)
                    .shadow(color: .black.opacity(0.42), radius: 105)
                    .shadow(color: .black.opacity(0.18), radius: 200)
            )
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

/// Запекание в одну GPU-текстуру на время движения. Парящие тени (три блюра до
/// 200px) в покое живут как есть — резкий вектор; на межэкранном переходе, где
/// групповая прозрачность иначе переблюривала бы их каждый кадр, контент
/// сплющивается в текстуру (.drawingGroup) и переход просто блитит её.
private struct FlattenWhileMoving: ViewModifier {
    let active: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if active { content.drawingGroup() } else { content }
    }
}

extension View {
    func floatShadow(_ radius: CGFloat) -> some View { modifier(FloatShadow(radius: radius)) }
    func edgeRelief(_ radius: CGFloat) -> some View { modifier(EdgeRelief(radius: radius)) }
    /// См. `FlattenWhileMoving`: `.drawingGroup()` только пока идёт переход.
    func flattenWhileMoving(_ active: Bool) -> some View {
        modifier(FlattenWhileMoving(active: active))
    }
    /// Курсор-рука на кликабельном. В макете (веб) у всего кликабельного
    /// `cursor: pointer`; в нативе по умолчанию курсор не меняется — вешаем
    /// системный link-указатель на каждую мишень, чтобы паритет держался.
    func clickCursor() -> some View { pointerStyle(.link) }
}

/// Обведённая галочка-кружок — единая форма факта на весь мастер (#ic-check):
/// кружок + галочка, монолиния, currentColor наследует цвет (везде sem-success).
struct CheckTick: View {
    var size: CGFloat = 13
    var color: Color = OB.success
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width
            let lw = s * 1.75 / 24
            var circle = Path()
            circle.addEllipse(
                in: CGRect(
                    x: s * (12 - 9.2) / 24, y: s * (12 - 9.2) / 24,
                    width: s * 18.4 / 24, height: s * 18.4 / 24))
            ctx.stroke(circle, with: .color(color), style: StrokeStyle(lineWidth: lw))
            var check = Path()
            check.move(to: CGPoint(x: s * 9 / 24, y: s * 12.3 / 24))
            check.addLine(to: CGPoint(x: s * 11 / 24, y: s * 14.3 / 24))
            check.addLine(to: CGPoint(x: s * 15.2 / 24, y: s * 9.6 / 24))
            ctx.stroke(
                check, with: .color(color),
                style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Кнопки

/// primary large — 44/32, squircle r18, плоский ультрамарин, hover/pressed вглубь.
/// Тайминг асимметричен: вход в hover 150ms, выход 450ms; тело не двигается.
struct OBPrimaryButton: View {
    let title: String
    var kbd: String? = nil
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    private var fill: Color { pressed ? OB.ultraPressed : (hovering ? OB.ultraHover : OB.ultramarine) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let kbd {
                    Text(kbd)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .padding(.horizontal, 5).padding(.top, 3).padding(.bottom, 2)
                        .background(OB.squircle(4).fill(Color.black.opacity(0.22)))
                        .overlay(
                            OB.squircle(4).strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                .mask(Rectangle().padding(.bottom, 12)))
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(height: 44)
            .padding(.horizontal, 32)
            // Тени — НА ФОРМЕ внутри .background, не на всей кнопке. У CSS box-shadow
            // тень отбрасывает только коробка; SwiftUI же `.shadow` на всём лейбле
            // кладёт гало и под текст (тёмный ореол по буквам). Кладём тень на
            // squircle-подложку, текст рисуется поверх без тени.
            .background {
                OB.squircle(18).fill(fill)
                    // микрорельеф кромок: свет сверху, подрезка снизу
                    .overlay(
                        OB.squircle(18).strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .clear, .black.opacity(0.44)],
                                startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    )
                    // как в макете: --shadow-soft (4 плотных контактных слоя) + широкий
                    // мягкий 0 6/18. Радиус SwiftUI ≈ CSS-блюр/2. Кнопка «садится» на
                    // поверхность, а не парит.
                    .shadow(color: .black.opacity(0.48), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.40), radius: 2.5, y: 2)
                    .shadow(color: .black.opacity(0.32), radius: 6, y: 6)
                    .shadow(color: .black.opacity(0.24), radius: 12, y: 12)
                    .shadow(color: .black.opacity(0.45), radius: 9, y: 6)
            }
        }
        .buttonStyle(.plain)
        .clickCursor()
        .animation(hovering ? OB.easeReal(0.15) : OB.easeReal(0.45), value: hovering)
        .animation(OB.easeReal(0.12), value: pressed)
        .onHover { hovering = $0 }
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
    }
}

/// ghost — вторичная кнопка с обводкой.
struct OBGhostButton: View {
    let title: String
    var action: () -> Void = {}
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OB.tSecondary)
                .frame(height: 28).padding(.horizontal, 12)
                .background(OB.squircle(6).fill(hovering ? Color.white.opacity(0.06) : .clear))
                .overlay(OB.squircle(6).strokeBorder(Token.Border.strong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .clickCursor()
        .onHover { hovering = $0 }
    }
}
