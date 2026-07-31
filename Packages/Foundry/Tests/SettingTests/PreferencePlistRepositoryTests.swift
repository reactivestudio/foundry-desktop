import Foundation
@testable import Setting
import Testing

@Suite("PreferencePlistRepository")
struct PreferencePlistRepositoryTests {
    private func uniqueDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    /// Репозиторий с явными кодерами — в тесте зависимости поставляет сам тест (то же
    /// конструкторное внедрение, что в проде даёт контейнер).
    private func makeRepository(in directory: URL) -> PreferencePlistRepository {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        return PreferencePlistRepository(
            location: StorageLocation(url: directory),
            encoder: encoder,
            decoder: PropertyListDecoder()
        )
    }

    @Test("Сохранённые настройки читаются обратно теми же значениями")
    func roundTrip() throws {
        let directory = uniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = makeRepository(in: directory)

        let id = try PreferenceId.of(value: "team")
        let preference = Preference.of(id: id)
        preference.change(theme: .dark)
        preference.toggleLaunchAtLogin()
        preference.disableNotification(for: .reviewNeeded)
        try preference.rename(firstName: "Ada", lastName: "Lovelace")
        repository.save(entity: preference)

        let loaded = try #require(repository.find(id: id))
        #expect(loaded.appearance.theme == .dark)
        #expect(loaded.general.launchAtLogin)
        #expect(loaded.notification.allows(type: .reviewNeeded) == false)
        #expect(loaded.notification.allows(type: .stageFinished))
        #expect(loaded.profile.fullName == "Ada Lovelace")
    }

    @Test("Аватар переживает round-trip")
    func avatarRoundTrip() throws {
        let directory = uniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = makeRepository(in: directory)

        let preference = Preference.of()
        try preference.change(avatar: Avatar.of(reference: "me.png"))
        repository.save(entity: preference)

        let loaded = try #require(repository.find(id: .default))
        #expect(loaded.profile.avatar?.reference == "me.png")
    }

    @Test("Снимок старого формата читается: недостающие ключи берут доменный дефолт")
    func olderSnapshotKeepsWhatItHas() throws {
        let directory = uniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Снимок, записанный кодом БЕЗ групп `Integration` и `Setup` (ключей просто нет).
        let stored: [String: Any] = ["theme": "dark", "launchAtLogin": true]
        let data = try PropertyListSerialization.data(
            fromPropertyList: stored, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("default.plist"))

        let loaded = try #require(makeRepository(in: directory).find(id: .default))

        // Что было в файле — сохранилось; чего не было — доменный дефолт, а не сброс набора.
        #expect(loaded.appearance.theme == .dark)
        #expect(loaded.general.launchAtLogin)
        #expect(loaded.integration.opensSessionInViewer)
        #expect(loaded.agent.selected == nil)
        #expect(loaded.setup.isFinished == false)
        #expect(loaded.general.tokensInKeychain)
        #expect(loaded.notification.allows(type: .stageFinished))
    }

    @Test("Связка с инструментами и первичная настройка переживают round-trip")
    func integrationAndSetupRoundTrip() throws {
        let directory = uniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = makeRepository(in: directory)

        let preference = Preference.of()
        preference.toggleOpensSessionInViewer()
        preference.change(agent: .geminiCli)
        preference.finishSetup()
        repository.save(entity: preference)

        let loaded = try #require(repository.find(id: .default))
        #expect(loaded.integration.opensSessionInViewer == false)
        #expect(loaded.agent.selected == ToolId.geminiCli)
        #expect(loaded.setup.isFinished)
    }

    @Test("Отсутствующий снимок — nil")
    func missingIsNil() {
        let repository = makeRepository(in: uniqueDirectory())
        #expect(repository.find(id: .default) == nil)
    }

    @Test("Битый файл — nil, без краша")
    func corruptIsNil() throws {
        let directory = uniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("не plist".utf8).write(to: directory.appendingPathComponent("default.plist"))

        let repository = makeRepository(in: directory)
        #expect(repository.find(id: .default) == nil)
    }
}
