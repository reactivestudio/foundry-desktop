import FoundryCore
import SwiftUI

/// Карточка одного элемента live-ленты.
struct FeedItemView: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(titleColor)

            if !item.body.isEmpty {
                Text(item.body)
                    .font(bodyFont)
                    .foregroundStyle(bodyColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var title: String {
        switch item.kind {
        case .info: "Система"
        case .thinking: "Мышление"
        case .text: "Ответ"
        case .tool(let name): name
        }
    }

    private var icon: String {
        switch item.kind {
        case .info: "info.circle"
        case .thinking: "brain"
        case .text: "text.bubble"
        case .tool: "wrench.and.screwdriver"
        }
    }

    private var titleColor: Color {
        switch item.kind {
        case .info: .secondary
        case .thinking: .purple
        case .text: .cyan
        case .tool: .blue
        }
    }

    private var bodyFont: Font {
        switch item.kind {
        case .thinking: .system(.callout).italic()
        case .tool: .system(.caption, design: .monospaced)
        default: .system(.callout)
        }
    }

    private var bodyColor: Color {
        switch item.kind {
        case .thinking: .init(white: 0.65)
        default: .init(white: 0.9)
        }
    }

    private var cardBackground: Color {
        switch item.kind {
        case .thinking: .init(red: 0.10, green: 0.07, blue: 0.16)
        case .tool: .init(red: 0.06, green: 0.09, blue: 0.16)
        default: .init(white: 0.09)
        }
    }
}

/// Финальная карточка result-события.
struct ResultCardView: View {
    let result: RunResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                result.isError ? "Завершено с ошибкой" : "Готово",
                systemImage: result.isError ? "xmark.octagon.fill" : "checkmark.seal.fill"
            )
            .font(.headline)
            .foregroundStyle(result.isError ? .pink : .cyan)

            if !result.text.isEmpty {
                Text(result.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 14) {
                metric("clock", format(durationMS: result.durationMS))
                if let cost = result.costUSD {
                    metric("dollarsign.circle", String(format: "$%.4f", cost))
                }
                metric("arrow.triangle.2.circlepath", "\(result.turns) ходов")
                metric("number", result.sessionID)
                    .help("Session ID сессии Claude Code")
                Button {
                    copyToPasteboard(result.sessionID)
                } label: {
                    Image(systemName: "document.on.document")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Скопировать session ID")
                Button {
                    copyToPasteboard("claude --resume \(result.sessionID)")
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Скопировать команду продолжения сессии в терминале")
                Button {
                    ClaudeDesktopLink.openSession(id: result.sessionID)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Открыть сессию в Claude Code Desktop")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: result.isError
                    ? [.init(red: 0.16, green: 0.05, blue: 0.10), .init(red: 0.10, green: 0.04, blue: 0.12)]
                    : [.init(red: 0.05, green: 0.09, blue: 0.18), .init(red: 0.09, green: 0.05, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        Label(value, systemImage: icon)
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func format(durationMS: Int) -> String {
        let seconds = Double(durationMS) / 1000
        return seconds < 60
            ? String(format: "%.1f с", seconds)
            : String(format: "%d мин %02d с", Int(seconds) / 60, Int(seconds) % 60)
    }
}
