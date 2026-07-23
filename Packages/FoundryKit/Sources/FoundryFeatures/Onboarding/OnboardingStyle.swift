import AppKit
import CoreGraphics
import SwiftUI

/// Онбординговые константы стиля — то, чего нет в `DesignTokens.swift`, но что
/// принято в макете (docs/design/mockups/onboarding.html): производные OKLCH
/// цвета кнопки, ступени янтарной плашки, парящая тень карточек, кегль hero.
///
/// Значения кнопки/янтаря посчитаны из OKLCH единожды и зашиты как sRGB —
/// SwiftUI не смешивает в OKLCH, а опорные точки макета фиксированы.
enum OB {
    // fon — самый нижний слой окна установки (#0E0B14, почти чёрный с чуть
    // фиолетовым тоном). Только фон окна; поверхности карточек/панелей — bg (ниже).
    static let fon = Color(hexValue: 0x0E0B14)
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

    // движение: делегируем в общий AppMotion (единый источник законов движения на
    // всё приложение). Здесь — лишь онбординговые алиасы, чтобы не трогать call-sites.
    /// «Настоящая» кривая макета cubic-bezier(0.2,0,0,1). См. `AppMotion.ease`.
    static func easeReal(_ d: Double) -> Animation { AppMotion.ease(d) }
    /// ЗАКОН ховера (быстро на входе, заметно медленнее на уходе) — общий на всё
    /// приложение. См. `AppMotion.hover`. Вешать как `.animation(OB.hoverAnim(h), value: h)`.
    static func hoverAnim(_ hovering: Bool) -> Animation { AppMotion.hover(hovering) }
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

/// Мелкодисперсный шум фона. Плоская заливка идеально однородна и оттого «мёртвая»;
/// лёгкий шум микрооттенков (как дизеринг в прототипе) оживляет фон — глазу почти
/// не виден, проступает лишь при увеличении. Тайл случайных значений вокруг
/// нейтрального серого 128, блендится `.overlay` (серый = без сдвига, отклонения
/// чуть светлят/темнят каждый пиксель; на тёмном фоне эффект пропорционально мал).
enum OBNoise {
    static let tile = 256  // сторона тайла, px (высокочастотный шум — швов не видно)
    static let amp = 27  // размах отклонения от серого 128 (± amp), 0…127
    static let opacity: Double = 0.7  // сила проявления (масштабирует отклонения)

    static let image: CGImage = make()

    private static func make() -> CGImage {
        let n = tile
        var px = [UInt8](repeating: 0, count: n * n * 4)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15  // детерминированный xorshift — стабилен между запусками
        func rnd() -> Int {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Int(truncatingIfNeeded: seed) & 0xFF
        }
        for i in 0..<(n * n) {
            let v = 128 + (rnd() % (2 * amp + 1)) - amp
            let g = UInt8(clamping: v)
            px[i * 4 + 0] = g
            px[i * 4 + 1] = g
            px[i * 4 + 2] = g
            px[i * 4 + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}

/// Фон окна установки: `OB.fon` с тонким шумом микрооттенков поверх (см. OBNoise).
struct FonBackground: View {
    var body: some View {
        OB.fon.overlay(
            // scale: 2 → один тексель шума = 1 физический пиксель на retina (самое
            // мелкое зерно); при scale 1 тексель занимал 1 point = 2 px, было крупнее.
            Image(decorative: OBNoise.image, scale: 2)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(OBNoise.opacity)
        )
        .compositingGroup()  // изолировать бленд шума на паре (fon+шум), не на рой ниже
    }
}

/// Тюнер тени карточек/панелей. Модель «spread + blur»: залитый чёрный силуэт,
/// вынесенный за кромку на `spread` px во все стороны, с размытием края на `blur` px.
enum OBShadow {
    static let spread: CGFloat = 80  // вынос за кромку во все стороны, px
    static let blur: CGFloat = 80  // размытие края, px (0 = чёткая граница)
    static let opacity: Double = 0.8  // прозрачность ВСЕГО слоя (после уплощения)
    static let color = Color.black
}

/// Один блок, отбрасывающий парящую тень: его рамка (anchor в координатах слоя)
/// и радиус угла. Собираются через preference и рисуются единым слоем.
struct ShadowCaster {
    let anchor: Anchor<CGRect>
    let radius: CGFloat
}

struct ShadowCastersKey: PreferenceKey {
    static let defaultValue: [ShadowCaster] = []
    static func reduce(value: inout [ShadowCaster], nextValue: () -> [ShadowCaster]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Пометить блок (карточку, панель) как отбрасыватель парящей тени: регистрирует
    /// его рамку в ближайшем `FloatShadowLayer`, а не рисует тень на месте. Так тень
    /// уходит в слой ПОД всем контентом экрана — см. FloatShadowLayer.
    func castsFloatShadow(_ radius: CGFloat) -> some View {
        anchorPreference(key: ShadowCastersKey.self, value: .bounds) {
            [ShadowCaster(anchor: $0, radius: radius)]
        }
    }
}

/// Единый слой парящих теней экрана. Собирает рамки всех `castsFloatShadow`
/// блоков и рисует их тени ОДНИМ слоем ПОД всем содержимым (заголовки, тексты,
/// карточки, панели, кнопки — всё рисуется выше). Поэтому тень одной карточки не
/// может лечь ни на соседнюю, ни на заголовок/лид/кнопку: тени на слое n, тела на
/// n+10. Раньше тень висела `.background`-ом ряда и, разрастаясь вверх, перекрывала
/// заголовок и лид (они рисуются в VStack раньше ряда) — это и был дефект модели.
struct FloatShadowLayer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.backgroundPreferenceValue(ShadowCastersKey.self) { casters in
            GeometryReader { proxy in
                // Залитые НЕПРОЗРАЧНЫЕ силуэты на (size+2·spread) → compositingGroup
                // (уплощает перекрытия в единое чёрное, без тёмных швов) → блюр края →
                // прозрачность на ВЕСЬ уплощённый слой (равномерно, не по прямоугольнику).
                ZStack {
                    ForEach(casters.indices, id: \.self) { i in
                        let rect = proxy[casters[i].anchor]
                        RoundedRectangle(cornerRadius: casters[i].radius, style: .continuous)
                            .fill(OBShadow.color)
                            .frame(
                                width: rect.width + 2 * OBShadow.spread,
                                height: rect.height + 2 * OBShadow.spread
                            )
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                .compositingGroup()
                .blur(radius: OBShadow.blur)
                .opacity(OBShadow.opacity)
            }
        }
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
    func edgeRelief(_ radius: CGFloat) -> some View { modifier(EdgeRelief(radius: radius)) }
    /// См. `FlattenWhileMoving`: `.drawingGroup()` только пока идёт переход.
    func flattenWhileMoving(_ active: Bool) -> some View {
        modifier(FlattenWhileMoving(active: active))
    }
    /// Курсор-рука на кликабельном. В макете (веб) у всего кликабельного
    /// `cursor: pointer`; в нативе по умолчанию курсор не меняется — вешаем
    /// системный link-указатель. Работает на КЛЮЧЕВОМ окне; на неактивном окне
    /// macOS свой курсор показывать почти не даёт — по договорённости не боремся.
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
        .animation(OB.hoverAnim(hovering), value: hovering)
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
        .animation(OB.hoverAnim(hovering), value: hovering)
        .onHover { hovering = $0 }
    }
}
