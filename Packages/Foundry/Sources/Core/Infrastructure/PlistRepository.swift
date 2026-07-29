import Foundation

/**
 Базовый файловый репозиторий на plist — механика чтения/записи `Codable`-снимка по
 имени (одна сущность = один `<name>.plist` в заданном каталоге). Наследники связывают
 его с конкретным портом репозитория и доменным маппингом (снимок ↔ агрегат), не
 переписывая файловую возню. Каталог и кодеры внедряются конструктором — репозиторий их
 НЕ создаёт: инстансы поставляет DIC (в тесте — сам тест). Так формат снимка (xml/binary)
 не зашит в код, а задаётся при сборке контейнера.

 `read` возвращает `nil`, если файла нет ИЛИ он не декодируется (порчу логируем, не
 роняем). `write` пишет атомарно; сбой записи логируется — операция небросающая, чтобы
 наследники-репозитории соблюдали небросающий порт. `open` — расширяется наследованием,
 напрямую не используется.
 */
open class PlistRepository<Snapshot: Codable> {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: PropertyListEncoder
    private let decoder: PropertyListDecoder

    public init(
        directory: URL,
        encoder: PropertyListEncoder,
        decoder: PropertyListDecoder,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.encoder = encoder
        self.decoder = decoder
        self.fileManager = fileManager
    }

    /// Прочитать снимок по имени; `nil` — файла нет ИЛИ он не декодируется (лог + `nil`).
    public func read(named name: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL(named: name)) else {
            return nil
        }

        do {
            return try decoder.decode(Snapshot.self, from: data)
        } catch {
            let reason = String(describing: error)
            FeatureLog.domain.error("Битый plist \(name, privacy: .public): \(reason, privacy: .public)")

            return nil
        }
    }

    /// Записать снимок под именем — атомарно; сбой записи логируется (небросающий).
    public func write(snapshot: Snapshot, named name: String) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL(named: name), options: .atomic)
        } catch {
            let reason = String(describing: error)
            FeatureLog.domain.error("Не сохранил \(name, privacy: .public): \(reason, privacy: .public)")
        }
    }

    private func fileURL(named name: String) -> URL {
        directory.appendingPathComponent("\(name).plist")
    }
}
