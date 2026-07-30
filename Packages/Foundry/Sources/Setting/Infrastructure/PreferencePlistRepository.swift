import Core
import Foundation
import SparkIoC

/**
 Адаптер порта `PreferenceRepository` на файловое хранилище: один набор настроек — один
 plist-файл (`<id>.plist`). Файловую механику несёт базовый `PlistRepository`, здесь —
 только связка с портом и доменный маппинг через `PreferenceSnapshot` (домен не
 `Codable`). Имя файла = `id.value` (маппинг id → имя живёт тут, в Infrastructure).

 `find` возвращает `nil`, если снимка нет ИЛИ он не бьётся с инвариантами домена (битый
 декод базовый класс уже отсеял и залогировал): наружу это «набор не сохранён», дефолт
 подставит use-case. `save` небросающий (сбой записи логирует база) — так требует порт.

 `@Repository` — стереотип бина слоя Infrastructure (адаптер-хранилище); скан выведет контракты из
 цепочки наследования сам (`PreferenceRepository` и конкретную базу `PlistRepository<PreferenceSnapshot>`).
 Все три зависимости — бины: каталог (`StorageLocation` из `Environment`) и кодеры приходят инъекцией.
 Один собственный designated-init — базовый `init(directory:…)` не наследуется, неоднозначности нет;
 тест подставляет свой `StorageLocation` с временным каталогом.
 */
@Repository
public final class PreferencePlistRepository: PlistRepository<PreferenceSnapshot>, PreferenceRepository {
    public init(
        location: StorageLocation,
        encoder: PropertyListEncoder,
        decoder: PropertyListDecoder
    ) {
        super.init(directory: location.url, encoder: encoder, decoder: decoder)
    }

    public func find(id: PreferenceId) -> Preference? {
        guard let snapshot = read(named: id.value) else {
            return nil
        }

        do {
            return try snapshot.toPreference(id: id)
        } catch {
            let reason = String(describing: error)
            FeatureLog.domain.error("Битый снимок \(id.value, privacy: .public): \(reason, privacy: .public)")

            return nil
        }
    }

    @discardableResult
    public func save(entity: Preference) -> Preference {
        write(snapshot: PreferenceSnapshot(from: entity), named: entity.id.value)

        return entity
    }
}
