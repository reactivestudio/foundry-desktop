import SwiftUI

/// Заголовок экрана — единственное место кегля 34 (type.hero). Тёмный ореол
/// цветом фона возвращает контраст над плотной серединой орба.
private struct OBTitle: View {
    let text: String
    var isStandalone = false
    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .bold))
            .tracking(-0.02 * 34)
            .foregroundStyle(OB.Text.primary)
            .shadow(color: OB.bg.opacity(0.85), radius: 6)
            .padding(.bottom, isStandalone ? 24 : 8)
    }
}

/// Лид экрана — две строки по формуле приветствия, центр, вторичный.
private struct OBSubtitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineSpacing(4.5)
            .multilineTextAlignment(.center)
            .foregroundStyle(OB.Text.secondary)
            .shadow(color: OB.bg.opacity(0.85), radius: 6)
            .padding(.bottom, 24)
    }
}

// MARK: - Экраны

struct WelcomeScreen: View {
    let onStart: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            FoundryWordmark(logoSize: 34)
                .padding(.bottom, 8)
            Text(
                "A delivery layer for changes: from task to\u{00a0}production\nAgents do routines, you review"
            )
            .font(.system(size: 12))
            .lineSpacing(4.5)
            .multilineTextAlignment(.center)
            .foregroundStyle(OB.Text.secondary)
            OBPrimaryButton(title: "Start setup", action: onStart)
                .padding(.top, 32)
        }
    }
}

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

struct SettingsScreen: View {
    let model: OnboardingModel
    var body: some View {
        VStack(spacing: 0) {
            OBTitle(text: "Settings", isStandalone: true)
            VStack(spacing: 0) {
                SetPanel {
                    ForEach(model.settings) { setting in
                        SettingRow(
                            name: setting.name, description: setting.description,
                            tappable: true, onTap: { model.toggle(setting.id) }
                        ) {
                            OBToggle(isOn: setting.isOn)
                        }
                    }
                }
                OBPrimaryButton(title: "Continue", action: { model.go(to: .permissions) })
                    .padding(.top, 32)
            }
            .padding(.top, 16)
        }
    }
}

struct PermissionsScreen: View {
    let model: OnboardingModel
    var body: some View {
        VStack(spacing: 0) {
            OBTitle(text: "Permissions")
            OBSubtitle(text: "macOS will ask twice\nBoth can wait until you actually need them")
            VStack(spacing: 0) {
                SetPanel {
                    ForEach(model.permissions) { permission in
                        SettingRow(name: permission.name, description: permission.description) {
                            GrantButton(
                                isGranted: permission.isGranted, action: { model.grant(permission.id) })
                        }
                    }
                }
                Text("Folder access comes later — macOS asks when you connect a project")
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OB.Text.tertiary)
                    .frame(maxWidth: 380)
                    .padding(.top, 16)
            }
            .padding(.top, 16)
        }
    }
}

struct ReadyScreen: View {
    let model: OnboardingModel
    private let rows: [(label: String, detail: String)] = [
        ("Agent", "Claude Code v2.1.4 · Max plan"),
        ("Extensions", "plugin 7 skills, 4 agents · foundry v0.4.1"),
        ("Settings", "Notch, notifications, Keychain, review"),
        ("Permissions", "Notifications · Accessibility ⌥ Space"),
    ]
    var body: some View {
        VStack(spacing: 0) {
            OBTitle(text: "Ready")
            OBSubtitle(text: "That's the whole setup\nFoundry takes it from here")
            VStack(spacing: 0) {
                SetPanel(maxWidth: 360) {
                    ForEach(rows, id: \.label) { row in
                        SettingRow(name: row.label, description: row.detail) {
                            CheckTick(size: 15)
                        }
                    }
                }
                OBPrimaryButton(title: "Start working", action: { model.finish() })
                    .padding(.top, 32)
            }
            .padding(.top, 16)
        }
    }
}
