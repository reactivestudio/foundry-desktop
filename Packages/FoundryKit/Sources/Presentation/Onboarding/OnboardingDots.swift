import SwiftUI

// MARK: - Пагинация

/// Шесть точек с жидким индикатором. Точки стоят на равном шаге и не разъезжаются
/// (слоты равной ширины). Индикатор — Shape, чья анимируемая величина = ДРОБНЫЙ
/// индекс активной точки: в покое пилюля-«линия», в полёте — метабол/перетекание.
/// Мишень каждой точки — высокий прямоугольник во всю ячейку (24×64, Фитс); клик,
/// ховер и курсор-палец — SwiftUI-нативные (.onTapGesture/.onHover/.clickCursor),
/// тот же pointerStyle(.link), что у кнопок Install/Allow/Skip мастера.
struct OnboardingDots: View {
    let count: Int
    let currentIndex: Int
    var onTap: (Int) -> Void = { _ in }

    // наведённый слот (кроме активного) — для подсветки
    @State private var hoveredIndex: Int?

    // Геометрия ряда — СТАТИКИ (единый источник), чтобы подвал (Skip) равнялся на
    // ту же линию точек. Слоты РАВНОЙ ширины: точки стоят намертво, при навигации
    // не рефлоу-ятся (прежний широкий активный слот двигал соседей — «разъехались»).
    static let slot: CGFloat = 24  // шаг ряда = мишень по X
    static let dot: CGFloat = 6
    static let pill: CGFloat = 18  // длина индикатора в покое — та самая «линия»
    // Мишень по Y — высокий ПОРТРЕТНЫЙ прямоугольник вокруг точки: тянется и ВВЕРХ,
    // и ВНИЗ под точку до самой нижней кромки окна (footer без нижнего отступа).
    // Видимая точка держится bottomPad от низа мишени = до кромки окна.
    static let hitHeight: CGFloat = 64
    static let bottomPadding: CGFloat = 24  // зазор точки от низа мишени = до кромки окна
    /// Вертикальный центр видимой точки от НИЗА ряда — на эту линию равняем Skip.
    static let dotCenterFromBottom: CGFloat = bottomPadding + dot / 2

    private var slot: CGFloat { Self.slot }
    private var dot: CGFloat { Self.dot }
    private var pill: CGFloat { Self.pill }
    private var hitHeight: CGFloat { Self.hitHeight }
    private var bottomPadding: CGFloat { Self.bottomPadding }
    private var dotCenterY: CGFloat { hitHeight - bottomPadding - dot / 2 }

    private var totalWidth: CGFloat { slot * CGFloat(count) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                // КНОПКА, а не onTapGesture: только настоящий контрол SwiftUI твёрдо
                // «захватывает» мишень в этом безрамочном прозрачном окне. С
                // onTapGesture ховер и курсор ПРОВАЛИВАЛИСЬ сквозь ряд в консоль под
                // мастером (RunConsoleView) — оттого и курсор поля ввода (I-beam).
                // Кнопка перекрывает провал; ← / → всё равно ведёт ArrowKeyMonitor.
                Button {
                    onTap(index)
                } label: {
                    DotSlot(
                        width: slot, height: hitHeight, dot: dot, bottomPadding: bottomPadding,
                        isPassed: index < currentIndex, isActive: index == currentIndex,
                        isHovering: hoveredIndex == index && index != currentIndex
                    )
                    // вся ячейка (высокий прямоугольник до нижней кромки) — мишень
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredIndex = $0 ? index : (hoveredIndex == index ? nil : hoveredIndex) }
                // палец — pointerStyle(.link), как у всех кнопок мастера. Регистрирует
                // курсор в РАЗРЕШЕНИИ курсора AppKit (переживает mouseMoved, в отличие
                // от NSCursor.push). Держится он лишь потому, что консоль на время
                // мастера инертна и не перебивает палец своим I-beam.
                .clickCursor()
            }
        }
        .frame(width: totalWidth, height: hitHeight)
        // Капля-метабол поверх ряда: пружина по дробному индексу, форму (дольки +
        // перешеек) рисует сам Shape. Хитов не ловит — клики идут в кнопки под ней.
        .overlay(
            LiquidBlob(
                fractionalIndex: CGFloat(currentIndex), slot: slot, pill: pill, dot: dot, y: dotCenterY
            )
            .fill(OB.ultramarine)
            .frame(width: totalWidth, height: hitHeight)
            .animation(.spring(response: 0.52, dampingFraction: 0.7), value: currentIndex)
            .allowsHitTesting(false)
        )
    }

    /// Жидкий индикатор: анимируемая величина — ДРОБНЫЙ индекс активной точки. В
    /// покое (у точки) — горизонтальная ПИЛЮЛЯ pill×dot, та самая «линия». В полёте
    /// не «гусеница» (пилюля постоянной длины ползёт), а жидкость: дольки сжимаются
    /// к кругам и расходятся (задняя отстаёт от передней), между ними — ВОГНУТЫЙ
    /// перешеек (поверхностное натяжение), тоньше на разлёте, как ртуть. У цели
    /// дольки снова разворачиваются в линию.
    private struct LiquidBlob: Shape {
        var fractionalIndex: CGFloat
        let slot: CGFloat
        let pill: CGFloat  // длина индикатора в покое
        let dot: CGFloat  // толщина (= диаметру серых точек)
        let y: CGFloat

        var animatableData: CGFloat {
            get { fractionalIndex }
            set { fractionalIndex = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let lower = fractionalIndex.rounded(.towardZero)
            let frac = fractionalIndex - lower
            func cx(_ i: CGFloat) -> CGFloat { slot * i + slot / 2 }
            let x0 = cx(lower)
            let x1 = cx(lower + 1)
            // задняя долька отстаёт от передней — перетекание, а не жёсткий сдвиг
            // (сильнее разводим/утончаем — длиннее нить, ярче ртутный разлёт)
            let headProgress = min(1, frac * 1.9)
            let tailProgress = max(0, frac * 1.9 - 0.9)
            let ax = x0 + (x1 - x0) * tailProgress
            let bx = x0 + (x1 - x0) * headProgress
            // у точки (frac→0/1) полуширина дольки = pill/2 (линия), на середине
            // сжимается к dot/2 (круг) — только так между дольками виден перешеек
            let tri = max(0, 1 - abs(frac - 0.5) * 2)  // 0 у точки, 1 на середине
            let halfH = dot / 2
            let halfW = (pill / 2) * (1 - tri) + halfH * tri
            return Self.metaball(ax: min(ax, bx), bx: max(ax, bx), y: y, halfW: halfW, halfH: halfH)
        }

        /// Две капсулы-дольки (в покое сливаются в одну «линию» pill×dot) + вогнутый
        /// перешеек между ними. Заливка nonzero объединяет всё в одно тело; перешеек
        /// тоньше на разлёте (утончение = натяжение).
        static func metaball(ax: CGFloat, bx: CGFloat, y: CGFloat, halfW: CGFloat, halfH: CGFloat) -> Path {
            func lobe(_ cx: CGFloat) -> CGRect {
                CGRect(x: cx - halfW, y: y - halfH, width: 2 * halfW, height: 2 * halfH)
            }
            let corner = CGSize(width: halfH, height: halfH)  // = капсула
            var p = Path()
            p.addRoundedRect(in: lobe(ax), cornerSize: corner, style: .continuous)
            let d = bx - ax
            guard d >= 0.5 else { return p }
            p.addRoundedRect(in: lobe(bx), cornerSize: corner, style: .continuous)
            // Перешеек-нить: КУБИКА с двумя контролами на уровне neck — длинная ровная
            // «шейка» тянущейся ртути (тоньше и изящнее одноконтрольной параболы,
            // касательные у долек мягче). Тоньше по мере разлёта.
            let neck = halfH * max(0.16, 1 - d / (5 * halfH))
            let cxL = ax + (bx - ax) * 0.30
            let cxR = bx - (bx - ax) * 0.30
            var n = Path()
            n.move(to: CGPoint(x: ax, y: y - halfH))
            n.addCurve(
                to: CGPoint(x: bx, y: y - halfH),
                control1: CGPoint(x: cxL, y: y - neck),
                control2: CGPoint(x: cxR, y: y - neck))
            n.addLine(to: CGPoint(x: bx, y: y + halfH))
            n.addCurve(
                to: CGPoint(x: ax, y: y + halfH),
                control1: CGPoint(x: cxR, y: y + neck),
                control2: CGPoint(x: cxL, y: y + neck))
            n.closeSubpath()
            p.addPath(n)
            return p
        }
    }

    private struct DotSlot: View {
        let width: CGFloat
        let height: CGFloat
        let dot: CGFloat
        let bottomPadding: CGFloat
        let isPassed: Bool
        let isActive: Bool
        let isHovering: Bool

        var body: some View {
            // Только визуал: точка у низа мишени. Клик/ховер/курсор — на кнопке.
            // На ховере меняется ТОЛЬКО цвет, размер прежний (просьба).
            ZStack(alignment: .bottom) {
                Color.clear
                Circle()
                    .fill(
                        isActive
                            ? .clear
                            : (isHovering
                                ? OB.ultramarine : Color.white.opacity(isPassed ? 0.38 : 0.20))
                    )
                    .frame(width: dot, height: dot)
                    .padding(.bottom, bottomPadding)
            }
            .frame(width: width, height: height)
            // быстро на входе, медленнее и плавнее на восстановлении
            .animation(OB.hoverAnim(isHovering), value: isHovering)
        }
    }
}
