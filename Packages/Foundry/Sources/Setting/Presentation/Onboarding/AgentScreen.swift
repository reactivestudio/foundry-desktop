import SwiftUI

struct AgentScreen: View {
    let model: OnboardingModel
    var body: some View {
        VStack(spacing: 0) {
            OBTitle(text: "Agent")
            OBSubtitle(text: "Foundry runs the stages, it writes no code\nChoose who does")
            HStack(spacing: 24) {
                ForEach(model.agents) { card in
                    AgentCard(
                        card: card,
                        isInstalled: model.installedAgents.contains(card.id),
                        isInstalling: model.installingAgent == card.id,
                        isSelected: model.selectedAgent == card.id,
                        onTap: { model.tapAgent(card.id) })
                }
            }
            .padding(.top, 16)
        }
    }
}
