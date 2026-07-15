# foundry-desktop

Нативное macOS-приложение (Swift/SwiftUI) — control plane над CRISPY-пайплайном
[foundry](https://github.com/reactivestudio/foundry): все проекты в одном окне,
богатое ревью артефактов каждой стадии, координация Claude Code.

Приложение — витрина и пульт, не движок. Закрыл приложение — всё продолжает
работать из терминала.

## Три слоя

| Слой | Роль |
|---|---|
| foundry-desktop (это репо) | инбокс ревью через все проекты, канбан change'ей, GitHub-style ревью артефактов, live-стрим работы Claude, аналитика лупов |
| bash-плагин `foundry` | источник правды: state machine, артефакты в `.foundry/`, enforcement — приложение **только шеллит** его, никогда не дублирует |
| Claude Code | исполнитель стадий: `claude -p` подпроцессом в каталоге проекта |

Несущие правила: правда — в файлах `.foundry/` под git проекта; мутации
состояния — только через `foundry` CLI; локальная БД (SQLite) — проекция +
app-only данные (треды ревью, настройки), никогда не источник правды.

## Принятые решения

- **Стек — чистый Swift/SwiftUI** (2026-07-14). Нативность — требование;
  ядро приложения (подпроцессы, FSEvents, git) — родная территория
  Foundation. Отклонены: Compose for Desktop (JVM/Skia, не нативно),
  SPA + Spring Boot (вкладка, не окно), KMP-ядро (два тулчейна ради тонкого
  слоя). Лок на Apple-экосистему принят осознанно.
- **Связь с плагином — контракт CLI**: `--plain`-вывод, exit-коды
  (`0/1/2/64`), структура `.foundry/` и `~/.foundry/projects/`.
  Контракт-тесты на фикстурах — в обоих репо.
- **Ревью-рендер** (markdown, diff, подсветка) — WKWebView-остров внутри
  нативного хрома.
- **iOS в будущем — тонкий клиент** (ревью + нотификации, разговаривает с
  маком); ядро на телефон не переезжает.
- **Mac App Store — никогда** (2026-07-15). Не отложено, а исключено: core loop
  спавнит `claude`/`foundry`/`git`, а дети наследуют песочницу — sandbox ломает
  саму суть приложения (глава 06 §7). Дистрибуция — только своя: Developer ID +
  notarization, Sparkle, DMG, Homebrew-tap. Notarization при этом **остаётся
  нужна** — она про Gatekeeper, а не про магазин.

## Вехи

| Веха | Содержание | Синхронизация с ядром foundry |
|---|---|---|
| D0 | Спайк петли: FSEvents-watch `.foundry/`, рендер артефакта, approve через CLI, прогон `claude -p` со стримингом и прерыванием | параллельно фазе 2 |
| D1 | Review MVP: change'и проекта, артефакт стадии, diff снапшот↔текущий, комментарии с типами, approve / request-changes | к первым LLM-артефактам (фаза 3), обязателен к фазе 4 |
| D2 | Оркестрация: запуск стадий из приложения, live-статус, доска | фазы 5–6 |
| D3 | Калибровка: очередь дельт, черновики патчей скиллов, approve | с первым calibrate (фаза 4+) |
| D4 | Аналитика (счётчик лупов) + кросс-проектный инбокс | после фазы 6 |

## Сборка и релизы

Внутренняя петля — пакет, без Xcode-проекта:

```sh
cd Packages/FoundryKit && swift test
```

Приложение целиком:

```sh
xcodebuild build -project FoundryDesktop.xcodeproj -scheme FoundryDesktop \
  -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- | xcbeautify
```

Дистрибутивы локально (ZIP + DMG в `dist/`):

```sh
./scripts/build-release.sh 0.1.0
```

CI (`.github/workflows/ci.yml`) на push/PR гоняет lint → тесты пакета → сборку
приложения.

### Как выпустить релиз

Релиз создаёт человек, сборку — GitHub Actions. Достаточно создать релиз в
GitHub с тегом вида `v0.1.0` (тег заводится там же, пушить его руками не нужно):

```sh
gh release create v0.1.0 --title "FoundryDesktop 0.1.0" --notes "Что нового…"
```

Дальше `release.yml` сам, по событию `release: published`: соберёт universal-бандл,
удалит с релиза дистрибутивы прошлой сборки, прикрепит свежие ZIP + DMG и
допишет в описание инструкцию по установке. Повторный запуск безопасен —
дистрибутивы заменяются, описание не дублируется.

Workflow удаляет только файлы вида `FoundryDesktop-*.dmg|zip`; всё, что
прикреплено к релизу руками, остаётся нетронутым.

`workflow_dispatch` у `release.yml` собирает те же дистрибутивы без релиза и
кладёт их в артефакты прогона — для проверки, ничего не публикуя.

### Установка скачанного билда

Сборки подписаны **ad-hoc**: Developer ID и notarization ещё не заведены, поэтому
Gatekeeper блокирует приложение при первом запуске. После перетаскивания в
`Applications`:

```sh
xattr -dr com.apple.quarantine /Applications/FoundryDesktop.app
```

Дельта к канону — практики,
[глава 08](docs/practices/08-project-tooling-distribution.md): Developer ID +
hardened runtime (§4.1), notarization (§4.2), Sparkle-автообновления (§4.3) и
Homebrew-tap (§4.5) не реализованы. Версия в `MARKETING_VERSION` берётся из тега,
`CURRENT_PROJECT_VERSION` — из `git rev-list --count HEAD` (§6.1).

## Статус

Пре-D0. Полный концепт и архитектура — `roadmap/foundry-desktop.md` в репо
плагина.
