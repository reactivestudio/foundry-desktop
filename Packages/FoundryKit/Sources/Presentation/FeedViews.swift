import Domain
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

/// Финальная карточка result-события. Всё, что зависит от исхода (заголовок,
/// знак, цвет, градиент), берёт у `ResultCardStyle`; метрики форматирует
/// `RunFormat`, команду продолжения чеканит `RunStrings` — вью только раскладывает.
struct ResultCardView: View {
    let result: RunResult
    /// Открыть эту сессию в Claude Code Desktop — интент стора (через порт), не
    /// прямой вызов инфраструктуры из вью.
    let onOpenInDesktop: () -> Void

    private var style: ResultCardStyle { ResultCardStyle(isError: result.isError) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(style.title, systemImage: style.icon)
                .font(.headline)
                .foregroundStyle(style.titleColor)

            if !result.text.isEmpty {
                Text(result.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 14) {
                metric("clock", RunFormat.duration(milliseconds: result.durationMilliseconds))
                if let cost = result.costUSD {
                    metric("dollarsign.circle", RunFormat.cost(usd: cost))
                }
                metric("arrow.triangle.2.circlepath", RunFormat.turns(result.turns))
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
                    copyToPasteboard(RunStrings.resumeCommand(sessionID: result.sessionID))
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Скопировать команду продолжения сессии в терминале")
                Button {
                    onOpenInDesktop()
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
                colors: style.background,
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
}
