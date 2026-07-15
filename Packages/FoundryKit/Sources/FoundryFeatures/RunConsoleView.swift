import FoundryCore
import SwiftUI

/// Главный экран прототипа D0: проект → промпт → live-лента → результат.
public struct RunConsoleView: View {
    @Environment(RunStore.self) private var store
    @AppStorage("projectDirectory") private var projectDirectory = ""

    public init() {}

    public var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.08))
            feed
            Divider().overlay(.white.opacity(0.08))
            promptArea
        }
        .background(Color(red: 0.03, green: 0.03, blue: 0.06))
        .preferredColorScheme(.dark)
        .frame(minWidth: 640, minHeight: 480)
    }

    // MARK: - шапка

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                pickProjectDirectory()
            } label: {
                Label(
                    projectDirectory.isEmpty
                        ? "Выбрать проект…"
                        : (projectDirectory as NSString).abbreviatingWithTildeInPath,
                    systemImage: "folder"
                )
                .lineLimit(1)
                .truncationMode(.head)
            }
            .help("Каталог проекта — в нём запустится claude")

            Spacer()

            ccdToggle

            permissionPicker

            OrbView(phase: store.phase)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var ccdToggle: some View {
        @Bindable var store = store
        return Toggle("в Claude Desktop", isOn: $store.openInClaudeDesktop)
            .toggleStyle(.checkbox)
            .help("Импортировать сессию в Claude Code Desktop при старте рана — ход работы будет виден и там")
    }

    private var permissionPicker: some View {
        @Bindable var store = store
        return Picker("Права", selection: $store.permissionMode) {
            Text("default").tag(PermissionMode.default)
            Text("accept edits").tag(PermissionMode.acceptEdits)
            Text("bypass").tag(PermissionMode.bypassPermissions)
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(store.phase.isRunning)
        .help("Permission mode headless-рана")
    }

    // MARK: - лента

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if store.feed.isEmpty && !store.phase.isRunning {
                    emptyState
                }
                ForEach(store.feed) { item in
                    FeedItemView(item: item)
                }
                if let result = store.result {
                    ResultCardView(result: result)
                }
                if case .failed(let message) = store.phase, store.result == nil {
                    failureCard(message)
                }
            }
            .padding(14)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(
                "Выбери проект, напиши промпт — claude запустится в его каталоге.\nСессию можно продолжить: claude --resume <id> из каталога проекта."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 120)
    }

    private func failureCard(_ message: String) -> some View {
        Label(message, systemImage: "xmark.octagon.fill")
            .foregroundStyle(.pink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(red: 0.16, green: 0.05, blue: 0.10),
                in: RoundedRectangle(cornerRadius: 10)
            )
    }

    // MARK: - промпт

    private var promptArea: some View {
        @Bindable var store = store
        return HStack(alignment: .bottom, spacing: 10) {
            TextEditor(text: $store.prompt)
                .font(.system(.body))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 76)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.1))
                )
                .disabled(store.phase.isRunning)

            VStack(spacing: 8) {
                if store.phase.isRunning {
                    Button(role: .cancel) {
                        store.stop()
                    } label: {
                        Label("Стоп", systemImage: "stop.fill")
                            .frame(width: 90)
                    }
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button {
                        startRun()
                    } label: {
                        Label("Запустить", systemImage: "play.fill")
                            .frame(width: 90)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canStart)
                }
            }
        }
        .padding(14)
    }

    private var canStart: Bool {
        !projectDirectory.isEmpty
            && !store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - действия

    public func startRun() {
        guard canStart, !store.phase.isRunning else { return }
        store.start(projectDirectory: projectDirectory)
    }

    private func pickProjectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Каталог проекта, в котором запустится claude"
        if panel.runModal() == .OK, let url = panel.url {
            projectDirectory = url.path
        }
    }
}
