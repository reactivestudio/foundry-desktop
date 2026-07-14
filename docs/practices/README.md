# Practices — Swift, SwiftUI и macOS для foundry-desktop

Серия документов о том, как мы пишем это приложение: общепринятые практики
разработки, дополненные спецификой Swift 6.x, SwiftUI и macOS — и привязанные
к архитектуре foundry-desktop (control plane над bash-плагином `foundry`:
подпроцессы, FSEvents, SQLite-проекция, WKWebView-остров ревью).

Актуальность зафиксирована на **июль 2026**: Swift 6.2.x (тулчейн Xcode 26;
«Swift 6.3» — open-source релиз swift.org, Apple-тулчейн слегка отстаёт) ·
Xcode 26 · сборка против macOS 26 SDK. Deployment target — **macOS 15
Sequoia** (решение 2026-07-14: машина разработчика на Sequoia, Liquid Glass
не цель). API, появившиеся в macOS 26 (`Observations`, SwiftUI `WebView`,
`.reorderable()`, `backgroundExtensionEffect()`…), — только за `#available`
и только когда fallback заметно хуже; нормы Liquid Glass в
[05](05-ui-design.md) — справка на будущее. Всё, что изменилось в 2024–2026 и противоречит старым статьям
и «знаниям LLM», в главах помечено блоками **«⚠️ Устарело»** — это самая
ценная часть серии: не дать затащить в код паттерны 2022 года.

## Как пользоваться

- **Пишешь код** (обычно Claude) — глава по теме открыта в контексте задачи;
  сквозные правила ниже соблюдаются всегда.
- **Ревьюишь код** (человек, Kotlin-бэкграунд) — в конце каждой главы
  «Чеклист ревью»; маппинг Kotlin → Swift — в [01](01-swift-language.md)
  и [02](02-swift-concurrency.md).
- Противоречие между главой и свежей документацией Apple → права документация,
  главу обновить в том же PR.

## Карта серии

| # | Глава | Про что | Когда открывать |
|---|---|---|---|
| 01 | [Swift: язык и идиомы](01-swift-language.md) | нейминг, value types, optionals, ошибки, память, Kotlin → Swift | любой Swift-код; ревью |
| 02 | [Swift 6: конкурентность](02-swift-concurrency.md) | actors, Sendable, structured concurrency, Approachable Concurrency 6.2 | всё асинхронное |
| 03 | [SwiftUI: архитектура и состояние](03-swiftui-architecture.md) | @Observable, MV без ViewModel'ей, поток данных файлы→UI, окна, производительность | экраны, сторы, сцены |
| 04 | [macOS: поведение нативного приложения](04-macos-platform.md) | меню-бар, шорткаты, окна, selection, undo, accessibility | любая новая команда/экран |
| 05 | [macOS: визуальный дизайн и UI-паттерны](05-ui-design.md) | Liquid Glass, типографика/плотность, цвет, SF Symbols, паттерны dev-инструментов | вёрстка, diff/лог-вьюеры |
| 06 | [Системная интеграция](06-system-integration.md) | swift-subprocess, стриминг `claude -p`, FSEvents, GRDB, git, WKWebView, sandbox | ядро приложения |
| 07 | [Тестирование и качество](07-testing-quality.md) | Swift Testing, contract-тесты foundry CLI, snapshot, os.Logger, swift format | тесты, CI-гейты |
| 08 | [Структура проекта, сборка, дистрибуция](08-project-tooling-distribution.md) | buildable folders + SPM-пакет, xcodebuild, подпись, notarization, Sparkle | скелет проекта, релизы |

## Сквозные принципы (действуют всегда)

Архитектурные — из [README](../../README.md) проекта, здесь как напоминание:

1. **Правда — в файлах `.foundry/`**; SQLite и память приложения — проекция.
   События FSEvents — подсказки «что перечитать», не данные.
2. **Мутации состояния — только через `foundry` CLI** (exit-коды `0/1/2/64`,
   `--plain`). Приложение никогда не дублирует state machine.
3. **Приложение — витрина и пульт, не движок**: закрыл окно — пайплайн жив.

Технологические — вердикты серии, принятые как дефолты:

4. **App-таргет — `@MainActor` by default** (Swift 6.2 Approachable
   Concurrency); фоновая работа — акторы-сервисы и `@concurrent`, в UI данные
   приходят батчами через `AsyncStream` → [02](02-swift-concurrency.md), [03](03-swiftui-architecture.md).
5. **MV, не MVVM**: `@Observable @MainActor` сторы + сервисы через
   environment; per-screen ViewModel'и не заводим → [03](03-swiftui-architecture.md).
6. **Подпроцессы — swift-subprocess**, не legacy `Process`;
   PATH резолвим сами (GUI не наследует shell) → [06](06-system-integration.md).
7. **БД — GRDB 7.x**, не SwiftData; git — шелл к CLI, не libgit2 → [06](06-system-integration.md).
8. **Sandbox — OFF** (дети наследуют песочницу); Developer ID + hardened
   runtime + notarization, апдейты Sparkle 2 → [06](06-system-integration.md), [08](08-project-tooling-distribution.md).
9. **Тесты — Swift Testing** (XCTest только для UI-smoke); формат — bundled
   `swift format` → [07](07-testing-quality.md).
10. **~95 % кода — в локальном SPM-пакете**, `.xcodeproj` — тонкий shell с
    buildable folders: агент правит файлы, pbxproj не трогается → [08](08-project-tooling-distribution.md).
11. **Нативность — не опция**: каждая команда — в меню-баре с шорткатом,
    text styles и семантические цвета вместо хардкода, плотность десктопа,
    dark mode с первого дня → [04](04-macos-platform.md), [05](05-ui-design.md).

## Если читаешь одно — прочитай это

Пять фактов, на которых чаще всего ловятся (подробности — в главах):

- **`ObservableObject`/`@Published` — legacy.** Только `@Observable`;
  view перерисовывается по факту чтения конкретного свойства.
- **«`await` в nonisolated func = фоновый поток» — больше неправда.**
  С Swift 6.2 `nonisolated async` бежит на акторе вызывающего; уход в фон —
  явный `@concurrent`.
- **`[weak self]` в каждом `Task` — карго-культ.** Task освобождает захваты
  по завершении; weak нужен только в долгоживущих `for await`-циклах.
- **`List` быстрее `LazyVStack` на больших данных** (recycling), а для
  лог-панели кодового качества всё ещё нужен `NSTextView`.
- **Иконку делать в Icon Composer** (слои, default/dark/mono): он отдаёт и
  классический вид для Sequoia, и Liquid Glass для macOS 26+ — один источник
  на оба мира.
