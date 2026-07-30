import SwiftUI

/// Экран частей Foundry: плагин агента и `foundry` CLI. Как и на экране агента,
/// установленность настоящая, а установка — дело пользователя: клик по неустановленной
/// части открывает инструкцию. Когда на месте обе — экран ведёт дальше.
struct ExtensionsScreen: View {
    let model: OnboardingModel
    let tool: ToolStore

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            OBTitle(text: "Extensions")
            OBSubtitle(
                text: "One teaches Claude Code the stages\nThe other runs them — worktrees, git, merges")
            HStack(spacing: 24) {
                ForEach(cards) { card in
                    AgentCard(card: card, isSelected: false, onTap: { tap(card: card) })
                }
            }
            .padding(.top, 16)
        }
        .task { await tool.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await tool.refresh()
                advanceIfReady()
            }
        }
    }

    private var cards: [InstallCardModel] {
        [
            card(
                id: .claudePlugin, glyph: .plugin, vendor: "Foundry", name: "Claude Plugin",
                requirement: "7 skills · 4 agents"),
            card(
                id: .foundryCli, glyph: .cli, vendor: "Foundry", name: "CLI",
                requirement: "stage runner · worktrees"),
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

        advanceIfReady()
    }

    /// Дальше — только когда на месте обе части: пустой снимок (систему ещё не
    /// спрашивали) сюда не проходит, `isInstalled` у него ложен.
    private func advanceIfReady() {
        guard cards.allSatisfy(\.isInstalled) else { return }
        model.extensionsReady()
    }
}
