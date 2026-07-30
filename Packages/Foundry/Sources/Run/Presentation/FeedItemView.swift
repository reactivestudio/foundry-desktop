import Core
import SwiftUI

/// Карточка одного элемента live-ленты. Всё оформление берёт у `FeedItemStyle` —
/// вью только раскладывает готовые значения.
struct FeedItemView: View {
    let item: TranscriptItem

    private var style: FeedItemStyle { FeedItemStyle(kind: item.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(style.title, systemImage: style.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(style.titleColor)

            if !item.body.isEmpty {
                Text(item.body)
                    .font(style.bodyFont)
                    .foregroundStyle(style.bodyColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let toolResult = item.toolResult, !toolResult.isEmpty {
                Text(toolResult)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(item.isError ? .pink : .secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.cardBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}
