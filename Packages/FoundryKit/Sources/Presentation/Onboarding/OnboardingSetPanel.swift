import SwiftUI

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
            .clipShape(OB.squircle(OB.cardRadius))
            .edgeRelief(OB.cardRadius)
            // тень рисует не панель: регистрируем рамку, слой кладёт тень под весь контент
            .castsFloatShadow(OB.cardRadius)
    }
}

/// Строка «имя · подпись» с правым слотом (тумблер, Allow или галочка).
struct SettingRow<Trailing: View>: View {
    let name: String
    let description: String
    var tappable: Bool = false
    var onTap: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(OB.Text.primary)
                // ВНИМАНИЕ: без .fixedSize. На экране Готово панель лежит прямо на
                // рое (без завесы), а .fixedSize(vertical:) на Text над непрозрачным
                // CAMetalLayer рендерится пустым И «отравляет» соседние композитные
                // слои того же кадра — гас весь контент, кроме роя. Подписи строк
                // однострочные при текущей ширине панели, перенос не нужен.
                Text(description).font(.system(size: 11)).foregroundStyle(OB.Text.tertiary)
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
    let isOn: Bool
    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? OB.ultramarine : Color.white.opacity(0.11))
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
        .animation(OB.easeReal(0.30), value: isOn)
    }
}

/// Кнопка Allow → «✓ Granted» (зелёный факт, больше не кнопка).
struct GrantButton: View {
    let isGranted: Bool
    let action: () -> Void
    @State private var isHovering = false
    var body: some View {
        if isGranted {
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
                    .background(OB.squircle(7).fill(isHovering ? OB.ultraHover : OB.ultramarine))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .animation(OB.hoverAnim(isHovering), value: isHovering)
            .onHover { isHovering = $0 }
        }
    }
}
