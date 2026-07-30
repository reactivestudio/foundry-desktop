import SwiftUI

/// Экран выбора агента: три CLI, состояние установки — настоящее (порт `ToolGateway`),
/// выбор — настоящая настройка (`Preference`, группа `Agent`). Установленный агент
/// выбирается кликом и ведёт дальше; неустановленный ставить приложение не берётся —
/// клик открывает инструкцию вендора, а установку экран заметит сам, когда пользователь
/// вернётся в окно.
struct AgentScreen: View {
    let model: OnboardingModel
    let tool: ToolStore
    let preference: PreferenceStore

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            OBTitle(text: "Agent")
            OBSubtitle(text: "Foundry runs the stages, it writes no code\nChoose who does")
            HStack(spacing: 24) {
                ForEach(cards) { card in
                    AgentCard(
                        card: card,
                        isSelected: preference.agent.selected == card.id,
                        onTap: { tap(card: card) })
                }
            }
            .padding(.top, 16)
        }
        .task { await tool.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await tool.refresh() }
        }
    }

    /// Тексты — из принятого прототипа, состояние — из стора инструментов. Строка
    /// установленного показывает версию, а если система её не назвала — просто факт
    /// установки: врать про версию хуже, чем её не знать.
    private var cards: [InstallCardModel] {
        [
            card(
                id: .claudeCode, glyph: .claude, vendor: "Anthropic", name: "Claude Code",
                requirement: "Pro / Max plan or API key"),
            card(
                id: .codexCli, glyph: .openai, vendor: "OpenAI", name: "Codex CLI",
                requirement: "ChatGPT plan or API key"),
            card(
                id: .geminiCli, glyph: .gemini, vendor: "Google", name: "Gemini CLI",
                requirement: "Google account · free tier"),
        ]
    }

    private func card(
        id: ToolId, glyph: OBGlyph, vendor: String, name: String, requirement: String
    ) -> InstallCardModel {
        let installation = tool.installation(of: id)

        return InstallCardModel(
            id: id, glyph: glyph, vendor: vendor, name: name, requirement: requirement,
            isInstalled: installation.isInstalled,
            installedLabel: installation.version.map { version in "v\(version)" } ?? "installed")
    }

    private func tap(card: InstallCardModel) {
        guard card.isInstalled else {
            tool.openInstructions(for: card.id)
            return
        }

        preference.change(agent: card.id)
        model.agentChosen()
    }
}
