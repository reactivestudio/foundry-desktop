import SwiftUI

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
