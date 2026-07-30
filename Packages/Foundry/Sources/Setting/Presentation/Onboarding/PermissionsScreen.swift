import SwiftUI

/// Экран разрешений мастера — настоящие диалоги macOS за портом `PermissionGateway`.
/// Своего «выдано» экран не держит: строка показывает то, что ответила система, а
/// перечитывается это при появлении экрана и при каждом возвращении в приложение —
/// универсальный доступ выдают не в диалоге, а в Системных настройках, и узнать об
/// этом можно только спросив заново.
struct PermissionsScreen: View {
    let model: OnboardingModel
    let permission: PermissionStore

    @Environment(\.scenePhase) private var scenePhase

    /// Просил ли пользователь разрешения ИМЕННО с этого экрана. Автопереход на финал
    /// разрешён только после его действия: иначе тот, у кого всё выдано давно, не смог
    /// бы даже вернуться на этот экран точками пагинации — первый же `refresh` кидал бы
    /// его вперёд.
    @State private var didRequest = false

    var body: some View {
        VStack(spacing: 0) {
            OBTitle(text: "Permissions")
            OBSubtitle(text: "macOS will ask twice\nBoth can wait until you actually need them")
            VStack(spacing: 0) {
                SetPanel {
                    ForEach(rows) { row in
                        SettingRow(name: row.name, description: row.description) {
                            GrantButton(isGranted: row.isGranted, action: { ask(row: row) })
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
        .task { await permission.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Вернулись из Системных настроек — спросить систему заново.
            guard phase == .active else { return }
            Task {
                await permission.refresh()
                advanceIfGranted()
            }
        }
    }

    /// Два разрешения = два вопроса системе. Тексты — из принятого прототипа, а «выдано
    /// ли» приходит из стора: строка это вид на ответ ОС, а не собственное состояние.
    private var rows: [PermissionRowModel] {
        [
            PermissionRowModel(
                id: .notifications, name: "Notifications",
                description: "A stage finished or needs your review",
                isGranted: permission.status(of: .notifications) == .granted,
                request: { await permission.request(kind: .notifications) }),
            PermissionRowModel(
                id: .accessibility, name: "Accessibility",
                description: "Global ⌥ Space and the notch panel",
                isGranted: permission.status(of: .accessibility) == .granted,
                request: { await permission.request(kind: .accessibility) }),
        ]
    }

    private func ask(row: PermissionRowModel) {
        didRequest = true
        Task {
            await row.request()
            advanceIfGranted()
        }
    }

    /// Все разрешения на руках — уходим на финал; решение о такте перехода остаётся у
    /// машины состояний мастера.
    private func advanceIfGranted() {
        guard didRequest, permission.allGranted else { return }
        model.permissionsGranted()
    }
}
