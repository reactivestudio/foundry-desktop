import SwiftUI

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
