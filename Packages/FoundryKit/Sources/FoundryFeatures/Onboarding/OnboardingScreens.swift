import SwiftUI

/// Заголовок экрана — единственное место кегля 34 (type.hero). Тёмный ореол
/// цветом фона возвращает контраст над плотной серединой орба.
private struct OBTitle: View {
    let text: String
    var solo = false
    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .bold))
            .tracking(-0.02 * 34)
            .foregroundStyle(OB.tPrimary)
            .shadow(color: OB.bg.opacity(0.85), radius: 6)
            .padding(.bottom, solo ? 24 : 8)
    }
}

/// Лид экрана — две строки по формуле приветствия, центр, вторичный.
private struct OBSub: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(5)
            .multilineTextAlignment(.center)
            .foregroundStyle(OB.tSecondary)
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
            Text("A delivery layer for changes: from task to\u{00a0}production\nAgents do routines, you review")
                .font(.system(size: 13))
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(OB.tSecondary)
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
            OBSub(text: "Foundry runs the stages, it writes no code\nChoose who does")
            HStack(spacing: 24) {
                ForEach(model.agents) { card in
                    AgentCard(
                        card: card,
                        installed: model.installedAgents.contains(card.id),
                        installing: model.installingAgent == card.id,
                        selected: model.selectedAgent == card.id,
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
            OBSub(text: "One teaches Claude Code the stages\nThe other runs them — worktrees, git, merges")
            HStack(spacing: 24) {
                ForEach(model.exts) { card in
                    AgentCard(
                        card: card,
                        installed: model.installedExts.contains(card.id),
                        installing: model.installingExt == card.id,
                        selected: false,
                        onTap: { model.tapExt(card.id) })
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
            OBTitle(text: "Settings", solo: true)
            VStack(spacing: 0) {
                SetPanel {
                    ForEach(model.settings) { s in
                        SettingRow(name: s.name, desc: s.desc,
                                   tappable: true, onTap: { model.toggle(s.id) }) {
                            OBToggle(on: s.on)
                        }
                    }
                }
                OBPrimaryButton(title: "Continue", action: { model.go(to: 4) })
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
            OBSub(text: "macOS will ask twice\nBoth can wait until you actually need them")
            VStack(spacing: 0) {
                SetPanel {
                    ForEach(model.permissions) { p in
                        SettingRow(name: p.name, desc: p.desc) {
                            GrantButton(granted: p.granted, action: { model.grant(p.id) })
                        }
                    }
                }
                Text("Folder access comes later — macOS asks when you connect a project")
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OB.tTertiary)
                    .frame(maxWidth: 380)
                    .padding(.top, 16)
            }
            .padding(.top, 16)
        }
    }
}

struct ReadyScreen: View {
    let model: OnboardingModel
    private let rows: [(String, String)] = [
        ("Agent", "Claude Code v2.1.4 · Max plan"),
        ("Extensions", "plugin 7 skills, 4 agents · foundry v0.4.1"),
        ("Settings", "Notch, notifications, Keychain, review"),
        ("Permissions", "Notifications · Accessibility ⌥ Space"),
    ]
    var body: some View {
        VStack(spacing: 0) {
            OBTitle(text: "Ready")
            OBSub(text: "That's the whole setup\nFoundry takes it from here")
            VStack(spacing: 0) {
                SetPanel(maxWidth: 360) {
                    ForEach(rows, id: \.0) { row in
                        SettingRow(name: row.0, desc: row.1) {
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
