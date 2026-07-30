import SwiftUI

struct ExtensionsScreen: View {
    let model: OnboardingModel
    var body: some View {
        VStack(spacing: 0) {
            OBTitle(text: "Extensions")
            OBSubtitle(
                text: "One teaches Claude Code the stages\nThe other runs them — worktrees, git, merges")
            HStack(spacing: 24) {
                ForEach(model.extensions) { card in
                    AgentCard(
                        card: card,
                        isInstalled: model.installedExtensions.contains(card.id),
                        isInstalling: model.installingExtension == card.id,
                        isSelected: false,
                        onTap: { model.tapExtension(card.id) })
                }
            }
            .padding(.top, 16)
        }
    }
}
