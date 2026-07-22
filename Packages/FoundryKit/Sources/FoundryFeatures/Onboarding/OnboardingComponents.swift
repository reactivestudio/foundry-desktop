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
        let radius: CGFloat = 0.6 * s
        let insets = EdgeInsets(
            top: 0.2 * s, leading: 0.45 * s,
            bottom: 0.275 * s, trailing: (0.5 - 0.06) * s)
        let plateGradient = LinearGradient(
            stops: [
                .init(color: OB.amberTop, location: 0),
                .init(color: OB.amberMid, location: 0.55),
                .init(color: OB.amberBottom, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        let highlight = LinearGradient(
            colors: [.white.opacity(0.45), .clear],
            startPoint: .top, endPoint: .bottom)
        let plate = OB.squircle(radius)
            .fill(plateGradient)
            .overlay(
                OB.squircle(radius)
                    .strokeBorder(highlight, lineWidth: max(0.5, 0.05 * s)))

        return Text("AI")
            .font(.system(size: s, weight: .bold))
            .tracking(0.06 * s)
            .foregroundStyle(OB.bg)
            // свет принадлежит буквам: 1px освещённой нижней губки выреза
            .shadow(color: .white.opacity(0.35), radius: 0, y: 0.1 * s)
            .padding(insets)
            .background(plate)
    }
}

// MARK: - Пагинация

/// Шесть точек с перетекающей каплей-индикатором. Активный слот шире (34 против
/// 22), капля-пилюля морфит между позициями; пройденные точки светлее, клик по
/// точке ведёт на шаг (мишень 22×24 по Фитсу).
struct OnboardingDots: View {
    let count: Int
    let current: Int
    var onTap: (Int) -> Void = { _ in }

    private let slot: CGFloat = 22
    private let slotActive: CGFloat = 34
    private let dot: CGFloat = 6
    // мишень 22×24 (точка 6px — рисунок): канонный hit по Фитсу (13 §10), как в макете
    private let height: CGFloat = 24

    private func slotWidth(_ i: Int) -> CGFloat { i == current ? slotActive : slot }

    // Точная своя ширина: ровно один активный слот шире. Без неё .position капли
    // ниже раздувает ZStack на всю доступную ширину, и ряд (alignment .leading)
    // прилипает влево — пагинация уезжала в левый нижний угол.
    private var totalWidth: CGFloat { slot * CGFloat(count - 1) + slotActive }

    // смещение центра активного слота от левого края ряда
    private var indicatorX: CGFloat {
        var x: CGFloat = 0
        for i in 0..<current { x += slotWidth(i) }
        return x + slotWidth(current) / 2
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    DotHit(
                        size: dot, height: height,
                        passed: i < current, active: i == current
                    )
                    .frame(width: slotWidth(i), height: height)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(i) }
                    .clickCursor()
                }
            }
            // капля-индикатор активной точки; `.ind` в макете pointer-events:none —
            // без этого капсула перехватывала ховер/клик над активной точкой, и
            // курсор-рука там не появлялся (мишень «съедена»).
            Capsule(style: .continuous)
                .fill(OB.ultramarine)
                .frame(width: slotActive - slot + dot, height: dot)
                .position(x: indicatorX, y: height / 2)
                .allowsHitTesting(false)
        }
        .frame(width: totalWidth, height: height)
        .animation(OB.easeReal(0.46), value: current)
    }

    private struct DotHit: View {
        let size: CGFloat
        let height: CGFloat
        let passed: Bool
        let active: Bool
        @State private var hovering = false
        var body: some View {
            Circle()
                .fill(active ? .clear : Color.white.opacity(passed ? 0.38 : 0.20))
                .frame(width: size, height: size)
                .scaleEffect(hovering && !active ? 1.5 : 1)
                .overlay {
                    if hovering && !active {
                        Circle().fill(OB.ultramarine).frame(width: size, height: size).scaleEffect(1.5)
                    }
                }
                .animation(OB.easeReal(0.22), value: hovering)
                .onHover { hovering = $0 }
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
                logo
                Text(card.vendor)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.08 * 8)
                    .foregroundStyle(OB.tTertiary)
                    .padding(.bottom, 2)
                Text(card.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OB.tPrimary)
                    .padding(.bottom, 4)

                if installed {
                    if let second = card.secondFact {
                        fact(second)
                    }
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
            .floatShadow(22)
        }
        .buttonStyle(.plain)
        .frame(width: 184, height: 184)
        .clickCursor()
        .onHover { hovering = $0 }
        .animation(OB.easeReal(0.15), value: selected)
    }

    // тайл знака: вендорская подложка (48) либо голый знак (24, оптический сдвиг влево)
    @ViewBuilder private var logo: some View {
        Group {
            if card.bare {
                glyphView
                    .frame(width: 24, height: 24, alignment: .leading)
                    .offset(x: -4)
                    .padding(.bottom, 12)
            } else {
                glyphView
                    .frame(width: 48, height: 48)
                    .background(OB.squircle(12).fill(card.tint ?? Color.white.opacity(0.07)))
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var glyphView: some View {
        switch card.glyph {
        case .claude: ClaudeGlyph(size: card.bare ? 24 : 26)
        case .openai: OpenAIGlyph(size: card.bare ? 24 : 26)
        case .gemini: GeminiGlyph(size: card.bare ? 24 : 26)
        case .plugin: PluginGlyph(size: 24)
        case .cli: CLIGlyph(size: 24)
        }
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .frame(height: 24)
            .padding(.horizontal, 10)
            .background(OB.squircle(7).fill(hovering && !installing ? OB.ultraHover : OB.ultramarine))
            .opacity(installing ? 0.6 : 1)
            .animation(hovering ? OB.easeReal(0.15) : OB.easeReal(0.45), value: hovering)
    }

    // нейтральная плашка (0.07→0.03); у выбранной добавлена синяя подкраска 0.06
    private var cardFill: some View {
        ZStack {
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
            .background(
                LinearGradient(
                    colors: [OB.cardFillTop, OB.cardFillBottom],
                    startPoint: .top, endPoint: .bottom)
            )
            .clipShape(OB.squircle(22))
            .overlay(
                OB.squircle(22).strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.05), .clear, .clear, .black.opacity(0.14)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .floatShadow(22)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(height: 24).padding(.horizontal, 10)
                    .background(OB.squircle(7).fill(hovering ? OB.ultraHover : OB.ultramarine))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .animation(hovering ? OB.easeReal(0.15) : OB.easeReal(0.45), value: hovering)
            .onHover { hovering = $0 }
        }
    }
}
