@testable import Setting

/**
 In-memory двойник порта `PreferenceRepository`: агрегат живёт в поле, а не в plist-файле.
 Тесты сценария и стора не трогают ни диск, ни каталог настроек пользователя — файловый
 срез проверяет отдельный `PreferencePlistRepositoryTests`.

 Считает записи (`saveCount`): так проверяется транзакционность — падающий интент не
 должен доходить до сохранения вовсе.
 */
final class InMemoryPreferenceRepository: PreferenceRepository {
    private var stored: [String: Preference] = [:]
    private(set) var saveCount = 0

    func find(id: PreferenceId) -> Preference? {
        stored[id.value]
    }

    @discardableResult
    func save(entity: Preference) -> Preference {
        saveCount += 1
        stored[entity.id.value] = entity

        return entity
    }
}
