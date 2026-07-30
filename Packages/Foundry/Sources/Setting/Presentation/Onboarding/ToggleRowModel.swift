/**
 Строка-тумблер экрана настроек мастера: что показать (имя, пояснение), в каком
 положении тумблер (`isOn`) и КАКОЕ НАМЕРЕНИЕ зовёт нажатие (`toggle`). Собственного
 состояния у строки нет: `isOn` читается из группы-VO агрегата через `PreferenceStore`,
 туда же уходит интент. Источник истины один — `Preference`, и «то, что видно» с «тем,
 что сохранено» разойтись не могут. Собирает строки `SettingsScreen`.
 */
struct ToggleRowModel: Identifiable {
    let id: String
    let name: String
    let description: String
    let isOn: Bool
    let toggle: () -> Void
}
