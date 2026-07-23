import AppKit
import SwiftUI

// MARK: - Логотип «Foundry AI»

/// Вордмарк + лейбл-знак «AI» единым компонентом (13 §9). Все внутренние меры —
/// в em от кегля знака: на базовом 34 попиксельно равны макету, на другом кегле
/// знак масштабируется целиком. Знак неделим — вордмарк без лейбла не живёт.
struct FoundryWordmark: View {
    var logoSize: CGFloat = 34
    private var em: CGFloat { logoSize / 34 }

    var body: some View {
        HStack(alignment: .top, spacing: 9 * em) {
            Text("Foundry")
                .font(.system(size: logoSize, weight: .bold))
                .tracking(-0.02 * logoSize)
                .foregroundStyle(OB.tPrimary)
            aiLabel
                // к верхней линии литер вордмарка, не к строке
                .padding(.top, 5 * em)
        }
        .fixedSize()
    }

    private var aiLabel: some View {
        let s: CGFloat = 10 * em  // кегль лейбла
        // Скругление — гиперэллипс (Squircle, суперэллипс n=4), радиус на ПОТОЛКЕ:
        // Squircle клампит угол в половину меньшей стороны, а меньшая здесь — высота
        // s + 0.25s + 0.27s = 1.52s, значит фактический угол = 0.76·s. Радиус задан
        // с запасом и всегда сидит на потолке — торцы остаются максимально круглыми
        // при любой высоте плашки, меняется лишь её пропорция.
        let radius: CGFloat = 1.0 * s
        // Поля от кегля лейбла. Низ чуть больше верха (+0.07·s) — у заглавных нет
        // нижних выносов, при равных полях они смотрятся просевшими.
        let insets = EdgeInsets(
            top: 0.25 * s, leading: 0.45 * s,
            bottom: 0.27 * s, trailing: (0.5 - 0.06) * s)
        let plateGradient = LinearGradient(
            stops: [
                .init(color: OB.amberTop, location: 0),
                .init(color: OB.amberMid, location: 0.55),
                .init(color: OB.amberBottom, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        let highlight = LinearGradient(
            colors: [.white.opacity(0.45), .clear],
            startPoint: .top, endPoint: .bottom)
        // Радиус уже на потолке (= половина высоты), расти ему некуда. Круглее делаем
        // ПОКАЗАТЕЛЕМ суперэллипса: n=3 вместо канонных 4 — угол ближе к дуге
        // окружности, размеры плашки при этом не меняются.
        let shape = Squircle(cornerRadius: radius, exponent: 3)
        let plate = shape
            .fill(plateGradient)
            .overlay(shape.strokeBorder(highlight, lineWidth: max(0.5, 0.05 * s)))

        return Text("AI")
            .font(.system(size: s, weight: .bold))
            .tracking(0.06 * s)
            .foregroundStyle(OB.bg)
            // свет принадлежит буквам: 1px освещённой нижней губки выреза
            .shadow(color: .white.opacity(0.35), radius: 0, y: 0.1 * s)
            // `line-height: 1` канона. У SwiftUI-Text бокс равен ЛИНЕЙНОЙ высоте
            // шрифта (~1.19·s у SF), и поля отсчитывались от неё — плашка выходила
            // на ~19% выше макетной: зазоры до текста больше, а гиперэллипс на
            // вытянутом боксе терял характер. Фиксируем бокс ровно в кегль.
            .frame(height: s)
            .padding(insets)
            .background(plate)
    }
}

// MARK: - Пагинация

/// Шесть точек с жидким индикатором. Точки стоят на равном шаге и не разъезжаются
/// (слоты равной ширины). Индикатор — Shape, чья анимируемая величина = ДРОБНЫЙ
/// индекс активной точки: в покое пилюля-«линия», в полёте — метабол/перетекание.
/// Мишень каждой точки — высокий прямоугольник во всю ячейку (24×64, Фитс); клик,
/// ховер и курсор-палец — SwiftUI-нативные (.onTapGesture/.onHover/.clickCursor),
/// тот же pointerStyle(.link), что у кнопок Install/Allow/Skip мастера.
struct OnboardingDots: View {
    let count: Int
    let current: Int
    var onTap: (Int) -> Void = { _ in }

    // наведённый слот (кроме активного) — для подсветки
    @State private var hovered: Int?

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
    static let bottomPad: CGFloat = 24  // зазор точки от низа мишени = до кромки окна
    /// Вертикальный центр видимой точки от НИЗА ряда — на эту линию равняем Skip.
    static let dotCenterFromBottom: CGFloat = bottomPad + dot / 2

    private var slot: CGFloat { Self.slot }
    private var dot: CGFloat { Self.dot }
    private var pill: CGFloat { Self.pill }
    private var hitHeight: CGFloat { Self.hitHeight }
    private var bottomPad: CGFloat { Self.bottomPad }
    private var dotCenterY: CGFloat { hitHeight - bottomPad - dot / 2 }

    private var totalWidth: CGFloat { slot * CGFloat(count) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                // КНОПКА, а не onTapGesture: только настоящий контрол SwiftUI твёрдо
                // «захватывает» мишень в этом безрамочном прозрачном окне. С
                // onTapGesture ховер и курсор ПРОВАЛИВАЛИСЬ сквозь ряд в консоль под
                // мастером (RunConsoleView) — оттого и курсор поля ввода (I-beam).
                // Кнопка перекрывает провал; ← / → всё равно ведёт KeyCatcher-монитор.
                Button { onTap(i) } label: {
                    DotSlot(
                        width: slot, height: hitHeight, dot: dot, bottomPad: bottomPad,
                        passed: i < current, active: i == current,
                        hovering: hovered == i && i != current
                    )
                    // вся ячейка (высокий прямоугольник до нижней кромки) — мишень
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
                // палец — pointerStyle(.link), как у всех кнопок мастера. Регистрирует
                // курсор в РАЗРЕШЕНИИ курсора AppKit (переживает mouseMoved, в отличие
                // от NSCursor.push). Раньше его перебивал I-beam консоли снизу — теперь
                // консоль на время мастера инертна, и палец наконец держится.
                .clickCursor()
            }
        }
        .frame(width: totalWidth, height: hitHeight)
        // Капля-метабол поверх ряда: пружина по дробному индексу, форму (дольки +
        // перешеек) рисует сам Shape. Хитов не ловит — клики идут в кнопки под ней.
        .overlay(
            LiquidBlob(fi: CGFloat(current), slot: slot, pill: pill, dot: dot, y: dotCenterY)
                .fill(OB.ultramarine)
                .frame(width: totalWidth, height: hitHeight)
                .animation(.spring(response: 0.52, dampingFraction: 0.7), value: current)
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
        var fi: CGFloat
        let slot: CGFloat
        let pill: CGFloat  // длина индикатора в покое
        let dot: CGFloat   // толщина (= диаметру серых точек)
        let y: CGFloat

        var animatableData: CGFloat {
            get { fi }
            set { fi = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let lower = fi.rounded(.towardZero)
            let frac = fi - lower
            func cx(_ i: CGFloat) -> CGFloat { slot * i + slot / 2 }
            let x0 = cx(lower), x1 = cx(lower + 1)
            // задняя долька отстаёт от передней — перетекание, а не жёсткий сдвиг
            // (сильнее разводим/утончаем — длиннее нить, ярче ртутный разлёт)
            let headP = min(1, frac * 1.9)
            let tailP = max(0, frac * 1.9 - 0.9)
            let ax = x0 + (x1 - x0) * tailP
            let bx = x0 + (x1 - x0) * headP
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
        let bottomPad: CGFloat
        let passed: Bool
        let active: Bool
        let hovering: Bool

        var body: some View {
            // Только визуал: точка у низа мишени. Клик/ховер/курсор — на кнопке.
            // На ховере меняется ТОЛЬКО цвет, размер прежний (просьба).
            ZStack(alignment: .bottom) {
                Color.clear
                Circle()
                    .fill(active ? .clear
                        : (hovering ? OB.ultramarine : Color.white.opacity(passed ? 0.38 : 0.20)))
                    .frame(width: dot, height: dot)
                    .padding(.bottom, bottomPad)
            }
            .frame(width: width, height: height)
            // быстро на входе, медленнее и плавнее на восстановлении
            .animation(OB.hoverAnim(hovering), value: hovering)
        }
    }
}

// MARK: - Карточка агента / расширения

enum OBGlyph { case claude, openai, gemini, plugin, cli }

/// Данные карточки. `bare` — часть Foundry без вендорской подложки тайла.
struct OBCard: Identifiable {
    let id: String
    let glyph: OBGlyph
    let bare: Bool
    let tint: Color?  // vtint подложки тайла
    let vendor: String
    let name: String
    let newFact: String  // факт/требование в состоянии «не установлено»
    let secondFact: String?  // вторая строка фактов у установленного (план и т.п.)
    let signed: String  // строка «✓ … signed in» после установки
    let showsInstall: Bool  // есть ли кнопка Install (у Claude в стенде уже стоит)
}

struct AgentCard: View {
    let card: OBCard
    let installed: Bool
    let installing: Bool
    let selected: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Верхний ряд: чип вендора слева, знак справа — оба к верхней кромке.
                // Снизу увеличенный зазор до имени (внешнее > внутреннего).
                HStack(alignment: .top, spacing: 8) {
                    vendorChip
                    Spacer(minLength: 8)
                    glyphView
                }
                .padding(.bottom, 4)
                Text(card.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OB.tPrimary)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if installed {
                    // secondFact — план/версия у агентов; у частей (plugin/cli) его нет,
                    // поэтому оставляем исходный факт-описание, иначе строка под именем
                    // исчезала при установке.
                    fact(card.secondFact ?? card.newFact)
                    Spacer(minLength: 0)
                    signedFact
                } else {
                    fact(card.newFact)
                    Spacer(minLength: 0)
                    if card.showsInstall { installButton }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(cardFill)
            .clipShape(OB.squircle(22))
            .overlay(selectionOverlay)
            .overlay(reliefOverlay)
            // тень рисует не карточка: регистрируем рамку, FloatShadowLayer кладёт
            // тень единым слоем под ВЕСЬ контент экрана (заголовок, лид, соседние
            // карточки — всё выше), чтобы тень ничьё тело не перекрывала
            .castsFloatShadow(22)
        }
        .buttonStyle(.plain)
        .frame(width: 184, height: 184)
        .clickCursor()
        .onHover { hovering = $0 }
        .animation(OB.easeReal(0.15), value: selected)
    }

    // Знак однотонный белый, БЕЗ подложки. Стоит в ПРАВОМ верхнем углу карточки
    // (паддинг 16 = отступ); чип вендора — в левом. Марка симметрична в своём
    // viewBox — гасим её ПРАВОЕ поле положительным сдвигом, чтобы знак был флеш с
    // правым краем карточки, а не утоплен влево.
    @ViewBuilder private var glyphView: some View {
        switch card.glyph {
        case .claude: ClaudeGlyph(size: 16).offset(x: 2)
        case .openai: OpenAIGlyph(size: 16).offset(x: 2.5)
        case .gemini: GeminiGlyph(size: 16).offset(x: 1)
        case .plugin: PluginGlyph(size: 14).offset(x: 3.5)
        case .cli: CLIGlyph(size: 14).offset(x: 3)
        }
    }

    // Чип вендора: ЗАГЛАВНЫЕ мельче имени, широкая разрядка, третичный, обведён
    // тонкой рамкой плотно по тексту (радиус 2.5). Правый паддинг чуть меньше —
    // разрядка добавляет пустоту после последней литеры, компенсируем.
    private var vendorChip: some View {
        Text(card.vendor)
            .font(.system(size: 7.5, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(OB.tTertiary)
            // Верх/низ не симметричны: заглавные без нижних выносов сидят выше
            // em-бокса → нижний паддинг на 1px меньше. Разрядка отодвигает текст
            // вправо → leading меньше trailing, текст стоит на 1px левее.
            .padding(.top, 3)
            .padding(.bottom, 2)
            .padding(.leading, 5)
            .padding(.trailing, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    private func fact(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(OB.tTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var signedFact: some View {
        HStack(spacing: 4) {
            CheckTick(size: 11)
            Text(card.signed)
        }
        .font(.system(size: 10))
        .foregroundStyle(OB.success)
    }

    private var installButton: some View {
        Text(installing ? "Installing…" : "Install")
            // кнопка целиком меньше при исходных пропорциях контейнера (h/кегль=2,
            // отступ/кегль=10/12): кегль 12→11, высота 24→22, отступ 10→9; радиус 7.
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .frame(height: 22)
            .padding(.horizontal, 9)
            .background(OB.squircle(7).fill(hovering && !installing ? OB.ultraHover : OB.ultramarine))
            .opacity(installing ? 0.6 : 1)
            .animation(OB.hoverAnim(hovering), value: hovering)
    }

    // нейтральная плашка (0.07→0.03); у выбранной добавлена синяя подкраска 0.06.
    // База — непрозрачный bg: плашка полупрозрачная, а тень-подложку ряда рисует
    // CardShadowRow отдельным слоем, так что своё непрозрачное дно нужно здесь.
    private var cardFill: some View {
        ZStack {
            OB.bg
            LinearGradient(
                colors: [OB.cardFillTop, OB.cardFillBottom],
                startPoint: .top, endPoint: .bottom)
            if selected { OB.ultramarine.opacity(0.06) }
        }
    }

    @ViewBuilder private var selectionOverlay: some View {
        if selected {
            OB.squircle(22).strokeBorder(OB.ultramarine.opacity(0.75), lineWidth: 2)
        }
    }

    private var reliefOverlay: some View {
        OB.squircle(22).strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.05), .clear, .clear, .black.opacity(0.14)],
                startPoint: .top, endPoint: .bottom),
            lineWidth: 1)
    }
}

// MARK: - Панель настроек / разрешений / резюме

/// Плашка `.setpanel` — та же нейтральная поверхность и угол 22, что у карточек;
/// внутри строки без разделительных линеек. Один компонент на Settings,
/// Permissions и резюме Ready.
struct SetPanel<Content: View>: View {
    var maxWidth: CGFloat = 340
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: maxWidth)
            // полупрозрачная плашка (свет сверху) поверх непрозрачной bg-базы, чтобы
            // рой не просвечивал; тень уходит в FloatShadowLayer — своё дно нужно тут
            .background(
                LinearGradient(
                    colors: [OB.cardFillTop, OB.cardFillBottom],
                    startPoint: .top, endPoint: .bottom)
            )
            .background(OB.bg)
            .clipShape(OB.squircle(22))
            .overlay(
                OB.squircle(22).strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.05), .clear, .clear, .black.opacity(0.14)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            // тень рисует не панель: регистрируем рамку, слой кладёт тень под весь контент
            .castsFloatShadow(22)
    }
}

/// Строка «имя · подпись» с правым слотом (тумблер, Allow или галочка).
struct SettingRow<Trailing: View>: View {
    let name: String
    let desc: String
    var tappable: Bool = false
    var onTap: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(OB.tPrimary)
                // ВНИМАНИЕ: без .fixedSize. На экране Готово панель лежит прямо на
                // рое (без завесы), а .fixedSize(vertical:) на Text над непрозрачным
                // CAMetalLayer рендерится пустым И «отравляет» соседние композитные
                // слои того же кадра — гас весь контент, кроме роя. Подписи строк
                // однострочные при текущей ширине панели, перенос не нужен.
                Text(desc).font(.system(size: 11)).foregroundStyle(OB.tTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .modifier(TapIf(active: tappable, action: onTap))
    }

    private struct TapIf: ViewModifier {
        let active: Bool
        let action: () -> Void
        func body(content: Content) -> some View {
            if active { content.onTapGesture(perform: action).clickCursor() } else { content }
        }
    }
}

/// Тумблер-индикатор 31×18: канавка всегда вдавлена, объём по свету; своего
/// клика нет — мишень по Фитсу вся строка.
struct OBToggle: View {
    let on: Bool
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(on ? OB.ultramarine : Color.white.opacity(0.11))
                .overlay(Capsule().strokeBorder(.white.opacity(0.05), lineWidth: 0.5))
                .overlay(  // канавка вдавлена сверху
                    Capsule().stroke(.black.opacity(0.5), lineWidth: 1.5)
                        .blur(radius: 0.5).mask(Capsule().padding(.bottom, 8)))
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(hexValue: 0xE9EBEF)],
                        startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                .padding(2)
        }
        .frame(width: 31, height: 18)
        .animation(OB.easeReal(0.30), value: on)
    }
}

/// Кнопка Allow → «✓ Granted» (зелёный факт, больше не кнопка).
struct GrantButton: View {
    let granted: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        if granted {
            HStack(spacing: 4) {
                CheckTick(size: 13)
                Text("Granted")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OB.success)
        } else {
            Button(action: action) {
                Text("Allow")
                    // тот же токен, что Install: кнопка целиком меньше, пропорции/радиус те же
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(height: 22).padding(.horizontal, 9)
                    .background(OB.squircle(7).fill(hovering ? OB.ultraHover : OB.ultramarine))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .animation(OB.hoverAnim(hovering), value: hovering)
            .onHover { hovering = $0 }
        }
    }
}
