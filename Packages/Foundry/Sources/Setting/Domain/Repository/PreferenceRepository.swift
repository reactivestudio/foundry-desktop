import Core

/**
 Интерфейс репозитория агрегата `Preference` — единственный репозиторий BC `Setting`
 (агрегат один; имя — по агрегату, не по контексту). Не переобъявляет сигнатуры, а
 УТОЧНЯЕТ базовый супертип `Repository`, связывая типы: агрегат — `Preference`, id —
 `PreferenceId`. Продакшн-реализация (plist в Application Support) внедряется корнем
 композиции, тест — in-memory-фейком.
 */
public protocol PreferenceRepository: Repository where Aggregate == Preference {}
