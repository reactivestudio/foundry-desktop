import Core
import SwiftUI

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
