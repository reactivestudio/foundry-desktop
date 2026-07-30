/// Каталог карточек мастера — что за агенты и расширения предлагаются в стенде
/// первого запуска. Это СИД-данные прототипа (визуальная имитация, реальные
/// инсталляции не подключены), отделённые от машины состояний `OnboardingModel`:
/// «какие карточки существуют» — не то же, что «как мастер ими управляет».
enum OnboardingCatalog {
    static let agents: [InstallCardModel] = [
        InstallCardModel(
            id: "claude", glyph: .claude,
            vendor: "Anthropic", name: "Claude Code",
            requirement: "Pro / Max plan or API key", installedDetail: "Max plan · Opus 4.8",
            signedInLabel: "v2.1.4 · signed in", showsInstall: true),
        InstallCardModel(
            id: "codex", glyph: .openai,
            vendor: "OpenAI", name: "Codex CLI",
            requirement: "ChatGPT plan or API key", installedDetail: "ChatGPT Pro · GPT-5.2",
            signedInLabel: "v0.9.2 · signed in", showsInstall: true),
        InstallCardModel(
            id: "gemini", glyph: .gemini,
            vendor: "Google", name: "Gemini CLI",
            requirement: "Google account · free tier", installedDetail: "Google account · free tier",
            signedInLabel: "v0.8.0 · signed in", showsInstall: true),
    ]

    static let extensions: [InstallCardModel] = [
        InstallCardModel(
            id: "plugin", glyph: .plugin,
            vendor: "Foundry", name: "Claude Plugin",
            requirement: "7 skills · 4 agents", installedDetail: nil,
            signedInLabel: "in ~/.claude", showsInstall: true),
        InstallCardModel(
            id: "cli", glyph: .cli,
            vendor: "Foundry", name: "CLI",
            requirement: "stage runner · worktrees", installedDetail: nil,
            signedInLabel: "/usr/local/bin/foundry", showsInstall: true),
    ]

    static let settings: [ToggleRowModel] = [
        ToggleRowModel(
            id: "notch", name: "Notch mode", description: "Stage progress around the notch", isOn: true),
        ToggleRowModel(
            id: "notif", name: "Notifications", description: "When a stage finishes or fails", isOn: true),
        ToggleRowModel(
            id: "keychain", name: "Keychain", description: "Tokens live there, not in files", isOn: true),
        ToggleRowModel(
            id: "login", name: "Launch at login", description: "Resumes stages after restart", isOn: false),
        ToggleRowModel(
            id: "review", name: "Merge review", description: "Nothing merges until you approve", isOn: true),
    ]

    static let permissions: [PermissionRowModel] = [
        PermissionRowModel(
            id: "notif", name: "Notifications", description: "A stage finished or needs your review",
            isGranted: false),
        PermissionRowModel(
            id: "a11y", name: "Accessibility", description: "Global ⌥ Space and the notch panel",
            isGranted: false),
    ]
}
