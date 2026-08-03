import SwiftUI

/// Экран настроек мастера — пять тумблеров прямо на агрегате `Preference`: строка
/// читает положение из стора и туда же адресует намерение, своего состояния у экрана
/// нет вовсе. Нажатие сохраняется сразу: мастер это не форма с «Применить», а тот же
/// набор настроек, показанный по шагам.
struct SettingsScreen: View {
    let model: SetupModel
    let preference: PreferenceStore

    var body: some View {
        VStack(spacing: 0) {
            SetupTitle(text: "Settings", isStandalone: true)
            VStack(spacing: 0) {
                SetPanel {
                    ForEach(rows) { row in
                        SettingRow(
                            name: row.name, description: row.description,
                            tappable: true,
                            onTap: { withAnimation(SetupStyle.easeReal(0.30)) { row.toggle() } }
                        ) {
                            SetupToggle(isOn: row.isOn)
                        }
                    }
                }
                SetupPrimaryButton(title: "Continue", action: { model.go(to: .permissions) })
                    .padding(.top, 32)
            }
            .padding(.top, 16)
        }
    }

    /// Пять строк = пять настоящих интентов стора. Тексты и порядок — из принятого
    /// прототипа, а начальные положения совпадают с доменными дефолтами (`Preference.of`),
    /// поэтому на чистой установке экран выглядит ровно как прежний сид.
    ///
    /// «Notifications» здесь ОДИН тумблер на всю группу видов — сворачивает их
    /// `toggleNotifications()` стора (см. его док); галочки по видам будут в окне
    /// настроек, где на них есть место.
    private var rows: [ToggleRowModel] {
        [
            ToggleRowModel(
                id: "notch", name: "Notch mode", description: "Stage progress around the notch",
                isOn: preference.appearance.notchEnabled,
                toggle: { preference.toggleNotch() }),
            ToggleRowModel(
                id: "notif", name: "Notifications", description: "When a stage finishes or fails",
                isOn: !preference.notification.isMuted,
                toggle: { preference.toggleNotifications() }),
            ToggleRowModel(
                id: "keychain", name: "Keychain", description: "Tokens live there, not in files",
                isOn: preference.general.tokensInKeychain,
                toggle: { preference.toggleTokensInKeychain() }),
            ToggleRowModel(
                id: "login", name: "Launch at login", description: "Resumes stages after restart",
                isOn: preference.general.launchAtLogin,
                toggle: { preference.toggleLaunchAtLogin() }),
            ToggleRowModel(
                id: "review", name: "Merge review", description: "Nothing merges until you approve",
                isOn: preference.general.mergeReview,
                toggle: { preference.toggleMergeReview() }),
        ]
    }
}
