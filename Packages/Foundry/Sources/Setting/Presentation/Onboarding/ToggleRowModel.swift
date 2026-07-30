/**
 Переключаемая строка экрана настроек мастера — ВРЕМЕННАЯ презентационная модель:
 имя, пояснение и состояние тумблера (сид в `OnboardingCatalog.settings`, мутабельное
 `isOn` держит `OnboardingModel`). Домена в ней нет и быть не должно — мастер это
 презентация BC `Setting`, а не второй источник истины. Уйдёт, когда экран сядет на
 настоящие команды агрегата `Preference`; тогда строка будет знать лишь, у какой
 команды она вызывает намерение.
 */
struct ToggleRowModel: Identifiable {
    let id: String
    let name: String
    let description: String
    var isOn: Bool
}
