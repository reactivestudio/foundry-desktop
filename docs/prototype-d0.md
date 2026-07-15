# Прототип D0 — «петля claude -p»

Дата: 2026-07-14 · Статус: требования согласованы, реализация в этой ветке.

## Зачем

Первый исполняемый срез D0 из [README](../README.md): доказать несущую петлю
приложения — **запуск Claude Code из нативного окна со live-стримом и
видимостью сессии в Claude Code Desktop**. Без этой петли остальное
(ревью, канбан, оркестрация стадий) не имеет фундамента.

Распространение — только локальная сборка (App Store не цель, подпись и
notarization — за рамками прототипа).

## Пользовательский сценарий (сквозной)

1. Открываю foundry-desktop, выбираю каталог проекта (любой git-репозиторий).
2. Пишу промпт в поле ввода, жму «Запустить» (⌘↩).
3. Приложение запускает `claude -p` подпроцессом **в каталоге проекта**.
4. Пока агент работает, в окне живая лента: мышление (thinking),
   вызовы инструментов с параметрами, текст ответа по токенам.
5. Параллельно в **Claude Code Desktop** вижу: в этом проекте появилась
   сессия (общее хранилище `~/.claude/projects/<путь>/<session-id>.jsonl`) —
   могу открыть её там и посмотреть/продолжить.
6. Claude завершился → в foundry-desktop финальная карточка результата:
   итоговый текст, длительность, стоимость, число ходов, session id.
7. Могу прервать ран кнопкой Stop (SIGINT → claude дописывает result).

## Функциональные требования

| # | Требование |
|---|---|
| F1 | Выбор каталога проекта через NSOpenPanel; путь запоминается между запусками (`@AppStorage`) |
| F2 | Поле промпта: многострочное, ⌘↩ — запуск, пока идёт ран — ввод заблокирован |
| F3 | Запуск `claude -p <prompt> --output-format stream-json --verbose --include-partial-messages` в выбранном каталоге, через swift-subprocess |
| F4 | Live-лента событий: system init (модель, session id), thinking-дельты, tool_use (имя + краткие параметры), tool result (сжатый), текст ответа по мере генерации |
| F5 | Финальная карточка `result`: текст, duration, cost USD, turns, session id; ошибка — отличима визуально |
| F6 | Stop: teardown-последовательность SIGINT → graceful; процесс не живёт дольше окна |
| F7 | Session id показан и копируется — по нему сессия находится в Claude Code Desktop |
| F8 | Выбор permission mode перед запуском: `default` / `acceptEdits` / `bypassPermissions` (дефолт — `acceptEdits`: headless-ран с «default» молча отклоняет правки) |
| F9 | Неизвестные типы событий не роняют ран: рендерятся как «неизвестное событие», сырой JSON — в лог |

## Нефункциональные требования

- **Стек и практики** — по [docs/practices](practices/README.md): Swift 6.2,
  SwiftUI, MV без ViewModel'ей (`@Observable @MainActor` стор), app-таргет
  `@MainActor` by default, swift-subprocess (не `Process`), deployment target
  macOS 15.
- **Структура** — тонкий `.xcodeproj` (buildable folders) + локальный SPM-пакет
  `Packages/FoundryKit` (гл. 08 §1.3); зависимости строго
  `FoundryFeatures → FoundryCore/FoundryCLI`, `FoundryCLI → FoundryCore`.
  Границы слоёв — по Clean Architecture (books): домен (события, модели ранов)
  не знает про subprocess и SwiftUI.
- **Отзывчивость UI**: токен-дельты коалессируются (~16 мс кадр), не
  по-событийные инвалидации SwiftUI (гл. 06 §2.5).
- **Надёжность стрима**: stderr дренируется конкурентно (анти-deadlock),
  разбор — только полными NDJSON-строками, толерантный декодер (гл. 06 §2.3–2.4).
- **Визуальное направление**: тёмное, чёрный/синий/пурпур, статусный «орб»
  как индикатор состояния рана (см. память проекта).
- Sandbox — OFF (наследование окружения подпроцессами), для локального
  прототипа подпись ad-hoc.

## Явно за рамками прототипа

- foundry CLI, `.foundry/`-стейт, FSEvents, SQLite/GRDB-проекция — следующий
  срез D0.
- Двунаправленная сессия (`--input-format stream-json`), resume, очередь ранов.
- Sparkle, notarization, CI.
- WKWebView-рендер markdown (в прототипе — плоский текст).

## Видимость сессий в Claude Code Desktop — выяснено (2026-07-14)

Проверено на живом ране и подтверждено документацией
([sessions](https://code.claude.com/docs/en/sessions.md),
[deep links](https://code.claude.com/docs/en/deep-links)):

- Сессия из `claude -p` попадает в общее хранилище
  `~/.claude/projects/<путь>/<session-id>.jsonl` и **резюмируется** через
  `claude --resume <session-id>` (в т.ч. в терминале CCD).
- В **session picker Desktop-приложения она не появляется** — это
  документированное ограничение: Desktop, CLI и VS Code ведут раздельные
  списки истории; picker CCD строится из его собственной метабазы
  (`~/Library/Application Support/Claude/local-agent-mode-sessions/`),
  записи которой создаёт только сам CCD. Инжектить туда записи — отказ:
  формат внутренний, завязан на процессы CCD.
- Deep links не решают: `claude-cli://open` открывает терминал (новая
  сессия, без resume существующей в GUI); `claude://code/new` — Cowork-tab.

Вердикт для продукта: **витрина live-хода — сам foundry-desktop** (что и
запланировано README); интеграция с CCD — на уровне «session id + команда
resume» из карточки результата. Появится официальный API/deep link «открыть
сессию» — добавим кнопку.

## Открытые вопросы

1. Хранение истории ранов в приложении (SQLite) — вместе со следующим срезом D0.
2. Замена `claude -p` на Agent SDK, если понадобится более плотный
   программный контроль (structured outputs, hooks) — сейчас избыточно.
