import SwiftUI

struct ReadyScreen: View {
    let model: SetupModel
    private let rows: [(label: String, detail: String)] = [
        ("Agent", "Claude Code v2.1.4 · Max plan"),
        ("Extensions", "plugin 7 skills, 4 agents · foundry v0.4.1"),
        ("Settings", "Notch, notifications, Keychain, review"),
        ("Permissions", "Notifications · Accessibility ⌥ Space"),
    ]
    var body: some View {
        VStack(spacing: 0) {
            SetupTitle(text: "Ready")
            SetupSubtitle(text: "That's the whole setup\nFoundry takes it from here")
            VStack(spacing: 0) {
                SetPanel(maxWidth: 360) {
                    ForEach(rows, id: \.label) { row in
                        SettingRow(name: row.label, description: row.detail) {
                            CheckTick(size: 15)
                        }
                    }
                }
                SetupPrimaryButton(title: "Start working", action: { model.finish() })
                    .padding(.top, 32)
            }
            .padding(.top, 16)
        }
    }
}
