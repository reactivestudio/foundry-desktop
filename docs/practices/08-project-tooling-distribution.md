# 08 · Структура проекта, сборка, дистрибуция

> Серия practices · [оглавление](README.md)

Контекст: foundry-desktop — SwiftUI-приложение (Swift 6.2.x, Xcode 26.x, target macOS 15),
solo-разработка, основной автор кода — AI-агент через CLI, дистрибуция вне Mac App
Store. Отсюда два сквозных требования этой главы: **всё собирается и проверяется из
терминала** и **проектные файлы детерминированы** (агент не должен трогать pbxproj).
Тестовые петли — в [главе 07](07-testing-quality.md), sandbox-вердикт — в
[главе 06](06-system-integration.md).

## TL;DR

| Вопрос | Решение |
|---|---|
| Структура | Тонкий `.xcodeproj` (buildable folders) + один локальный SPM-пакет с ~95% кода |
| Генераторы проекта | Не нужны (⚠️ Tuist/XcodeGen — избыточны на solo-масштабе) |
| Pure-SPM app | ⚠️ Отклонено (swift-bundler — мимо notarization/Sparkle) |
| Сборка | `swift build/test` (пакет) + `xcodebuild \| xcbeautify` (приложение) |
| Зависимости | SPM, `Package.resolved` в git, минимум пакетов (таблица §4) |
| Подпись | Developer ID + hardened runtime, **без** App Sandbox |
| Notarization | `notarytool submit --wait` + `stapler staple` |
| Обновления | Sparkle 2 (EdDSA, appcast на GitHub Releases, ZIP) |
| Сайт | DMG через create-dmg; Homebrew — свой tap |
| CI | GitHub Actions `macos-26`, SPM-кэш, p12→временный keychain, ASC API key |
| Релизы | MARKETING_VERSION/CURRENT_PROJECT_VERSION, justfile; ⚠️ fastlane не нужен |

---

## 1. Структура проекта

### 1.1 Buildable folders: pbxproj перестаёт быть проблемой

**Правило.** Проект создаётся в Xcode 16+ (у нас — Xcode 26.x) с **buildable
folders** (`PBXFileSystemSynchronizedRootGroup`): app-таргет ссылается на
*каталог*, и Xcode подхватывает все файлы внутри автоматически.

**Почему.** Классический pbxproj перечислял каждый файл — любое добавление/переименование
требовало мутации бинарно-подобного plist, чего AI-агент из CLI делать не должен.
С buildable folders агент **добавляет/переименовывает/удаляет Swift-файлы чистыми
FS-операциями** — pbxproj не меняется вообще. Проект становится почти
append-only-артефактом: создан один раз, дальше меняется только при добавлении
таргетов, capabilities или зависимостей самого app-таргета.

⚠️ Устарело: скрипты правки pbxproj (xcodeproj gem, mod-pbxproj), ритуал «открой
Xcode и добавь файл в таргет». Существующие группы конвертируются правым кликом →
«Convert to Folder»; нового формата проекта взамен pbxproj в Xcode 26/27 нет —
buildable folders и есть официальная митигация.

### 1.2 Тонкий shell + один локальный SPM-пакет

**Правило.** В `.xcodeproj` живёт только app-таргет-обёртка (`@main`, entitlements,
ассеты, Info-настройки, XCUITest-бандл). ~95% кода — в **одном** локальном
SPM-пакете с несколькими таргетами.

**Почему.**

- `Package.swift` — обычный детерминированный Swift-текст, агент правит его напрямую.
- `swift build` / `swift test` в пакете работают без Xcode build system — быстрая
  внутренняя петля (см. §3 и [главу 07 §8](07-testing-quality.md)).
- Границы модулей навязываются графом пакета: UI не может «случайно» заимпортить
  слой процессов в обход домена.
- Один пакет, много таргетов (а не россыпь пакетов): один `Package.swift` на
  сопровождении, один `swift test` гоняет всё, изоляция модулей — та же.

Apple документирует этот паттерн («Organizing your code with local packages»);
он же — консенсус сообщества для 2024–2026.

### 1.3 Конкретный layout foundry-desktop

```
foundry-desktop/
├── Foundry.xcodeproj               # тонкий: app-таргет + UITests, buildable folder → App/
├── App/                            # buildable folder
│   ├── FoundryApp.swift            # @main, wiring: собирает зависимости, отдаёт в FoundryKit
│   ├── Foundry.entitlements
│   ├── Assets.xcassets
│   └── Info-additions              # SUFeedURL, SUPublicEDKey и пр. (build settings / Info.plist keys)
├── Packages/
│   └── FoundryKit/                 # ЕДИНСТВЕННЫЙ локальный пакет
│       ├── Package.swift
│       ├── Sources/
│       │   ├── FoundryCore/        # домен: модели, чистая логика; зависимостей — минимум
│       │   ├── FoundryCLI/         # слой foundry CLI: CommandRunning, парсеры вывода (swift-subprocess)
│       │   ├── FoundryStore/       # персистентность (GRDB)
│       │   ├── FoundryDesignSystem/# общие SwiftUI-компоненты, стили (главы 03/04)
│       │   └── FoundryFeatures/    # фичи-экраны: sidebar, project detail, run console…
│       └── Tests/
│           ├── FoundryCoreTests/
│           ├── FoundryCLITests/    # + Fixtures/ (голдены, fake-исполняемые — глава 07 §3)
│           ├── FoundryStoreTests/
│           └── FoundryFeaturesTests/   # снапшоты
├── UITests/                        # XCUITest smoke (≤5 тестов, глава 07 §5)
├── scripts/
│   ├── ExportOptions.plist         # method=developer-id
│   └── release.sh                  # или рецепты в justfile
├── .swift-format
├── justfile
├── CHANGELOG.md
└── .github/workflows/{ci.yml, release.yml}
```

Направление зависимостей внутри пакета (навязано `Package.swift`):

```
FoundryFeatures → FoundryDesignSystem, FoundryCore, FoundryCLI, FoundryStore
FoundryCLI      → FoundryCore (+ swift-subprocess)
FoundryStore    → FoundryCore (+ GRDB)
FoundryCore     → (только stdlib / swift-collections)
```

App-таргет импортирует `FoundryFeatures` и делает wiring — больше ничего.

### 1.4 Отклонённые альтернативы

| Вариант | Статус (2026) | Вердикт для foundry-desktop |
|---|---|---|
| Raw `.xcodeproj` + buildable folders | Встроено, Xcode 16+ | **Принято**: ноль лишнего тулинга, файлы — чистые FS-операции |
| XcodeGen | 2.45.x, сопровождается, но медленно | Не нужен: даёт «проект как YAML», но добавляет шаг регенерации, который агент обязан помнить. Запасной выход, если pbxproj вдруг придётся часто скриптовать |
| Tuist | Очень активен, Swift DSL, кэширование | Overkill: ценность — на больших мультикомандных монорепо. Solo-репо с одним приложением не окупает слой |
| Pure SPM + swift-bundler | swift-bundler жив (~500★), ниша | ⚠️ **Отклонено**: `swift build` не делает `.app`-бандл, а swift-bundler уводит с паваной дороги entitlements → hardened runtime → встраивание Sparkle → notarization → Instruments → SwiftUI previews. Для подписанного самообновляющегося приложения — нет |

---

## 2. CLI-сборка: как агент собирает и проверяет

### 2.1 Двухуровневая петля

1. **Inner loop (пакет)** — секунды, без подписи и Xcode-проекта:

```bash
cd Packages/FoundryKit
swift build
swift test
```

2. **Integration loop (приложение)** — перед коммитом и в CI:

```bash
# Сборка приложения без подписи (локальная проверка)
set -o pipefail && xcodebuild build \
  -project Foundry.xcodeproj -scheme Foundry \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGN_IDENTITY=- \
  | xcbeautify

# Полные тесты с result bundle
set -o pipefail && xcodebuild test \
  -project Foundry.xcodeproj -scheme Foundry \
  -destination 'platform=macOS,arch=arm64' \
  -resultBundlePath .build/Tests.xcresult \
  | xcbeautify
```

Правила:

- `set -o pipefail` при пайпе в форматтер — обязателен, иначе провал xcodebuild
  съедается успешным exit-кодом xcbeautify.
- **xcbeautify** (3.x, активен, предустановлен на GitHub-раннерах) — текущий
  форматтер; ⚠️ Устарело: xcpretty не сопровождается.
- `-destination 'platform=macOS,arch=arm64'`: симуляторов на macOS нет, тесты идут
  на хосте — CLI-прогон детерминированнее, чем на iOS.
- `-derivedDataPath .build/DerivedData` — предсказуемые пути (запуск собранного
  приложения, кэш в CI).
- Машиночитаемый разбор результатов (агент парсит JSON, не логи):

```bash
xcrun xcresulttool get test-results summary --path .build/Tests.xcresult
xcrun xcresulttool get test-results tests   --path .build/Tests.xcresult
```

- Smoke-запуск собранного приложения:
  `open .build/DerivedData/Build/Products/Debug/Foundry.app`
  (или бинарь напрямую, чтобы снять stdout).
- Интроспекция проекта: `xcodebuild -list -json`.

---

## 3. Зависимости: SPM-дисциплина

**Правила.**

1. **`Package.resolved` коммитится** — и пакетный
   (`Packages/FoundryKit/Package.resolved`), и проектный
   (`Foundry.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`).
   Иначе CI и локальная машина резолвят разное.
2. Пиннинг: `from: "X.Y.Z"` (up-to-next-major) для стабильных ≥1.0;
   **`.upToNextMinor`** для 0.x (SPM считает 0.x-миноры breaking) — актуально для
   swift-subprocess и swift-markdown.
3. `swift package update` — только осознанно и **отдельным коммитом**.
4. Каждая новая зависимость — это supply-chain-поверхность и ставка на чужое
   сопровождение; в PR обосновывается, почему нельзя обойтись stdlib/Apple-пакетом.

```swift
// Packages/FoundryKit/Package.swift — фрагмент
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.6.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.0"),
    .package(url: "https://github.com/swiftlang/swift-subprocess", .upToNextMinor(from: "0.5.0")),
    .package(url: "https://github.com/swiftlang/swift-markdown", .upToNextMinor(from: "0.8.0")),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.0"), // test-only
]
```

Sparkle подключается к **app-таргету в xcodeproj** (ему нужно встраивание
XPC/Autoupdate-компонентов в бандл), а не к пакету.

**Проверенный список (статусы верифицированы по GitHub, июль 2026):**

| Пакет | Версия | Статус | Роль |
|---|---|---|---|
| GRDB.swift | 7.11.1 | Отлично, активен | Локальный SQLite (FoundryStore) |
| Sparkle | 2.9.4 | Очень активен | Обновления вне MAS (§5.3) |
| swift-collections | 1.6.0 | Активен (Apple) | Deque, OrderedDictionary… |
| swift-async-algorithms | 1.1.5 | Активен (Apple) | debounce/merge/chunked на AsyncSequence |
| swift-subprocess | 0.5 | Активен (Swift.org), **pre-1.0 — пин minor** | Замена Foundation.Process |
| swift-markdown | 0.8.0 | Активен, 0.x — пин minor | Рендер markdown из CLI-вывода |
| Highlightr | 2.3.0 | Полуактивен, приемлем | Подсветка кода (JS-мост; при боли — tree-sitter) |
| swift-snapshot-testing | 1.19.3 | Активен | Только test-таргеты |
| swift-log | 1.14.0 | Активен | Только если извлечём переносимую библиотеку (глава 07 §6) |
| ~~Splash~~ | 0.16.0 (2021) | ⚠️ **Дормантен — не использовать** | — |

---

## 4. Дистрибуция вне App Store

### 4.1 Подпись: Developer ID + hardened runtime, без sandbox

**Правило.** Приложение подписывается сертификатом **Developer ID Application** с
включённым **hardened runtime** (обязателен для notarization). **App Sandbox —
выключен**: foundry-desktop — dev-tool, который спавнит произвольные процессы и
читает проекты пользователя по всей ФС; sandbox блокирует exec и усложняет Sparkle.
Развёрнутое обоснование — [глава 06](06-system-integration.md).

**Entitlements-минимум.** Спавн подпроцессов под hardened runtime **не требует
никаких entitlements**. Исключения добавляются только при реальной необходимости:

| Entitlement | Когда (и только тогда) |
|---|---|
| `com.apple.security.cs.disable-library-validation` | Загрузка сторонних плагинов/dylib |
| `com.apple.security.cs.allow-jit` | JIT |
| `com.apple.security.automation.apple-events` (+ usage description) | Скриптинг других приложений |

Стартовый `Foundry.entitlements` — **пустой словарь**. Каждый добавленный
ключ — отдельное ревью.

**Подпись — inside-out, никогда `--deep`.** Вложенные компоненты (Sparkle:
`Autoupdate`, `Updater.app`, XPC-сервисы) подписываются раньше приложения; Xcode
archive/export делает это корректно сам:

```bash
xcodebuild archive \
  -project Foundry.xcodeproj -scheme Foundry \
  -destination 'platform=macOS' \
  -archivePath .build/Foundry.xcarchive

xcodebuild -exportArchive \
  -archivePath .build/Foundry.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath .build/export
# ExportOptions.plist: method=developer-id, signingStyle=automatic
```

Гочи: каждый вложенный исполняемый файл обязан быть подписан Developer ID с
hardened runtime и secure timestamp — иначе notarization отклонит весь бандл.
Sparkle ставится как «Embed & Sign», его компоненты не перепаковывать вручную.

### 4.2 Notarization

⚠️ Устарело: `altool` мёртв. Только `notarytool`:

```bash
ditto -c -k --keepParent .build/export/Foundry.app .build/Foundry.zip

xcrun notarytool submit .build/Foundry.zip \
  --keychain-profile "notary" --wait
# профиль один раз: xcrun notarytool store-credentials notary --key AuthKey.p8 --key-id … --issuer …

xcrun stapler staple .build/export/Foundry.app   # офлайн-валидация Gatekeeper

# Верификация перед публикацией
codesign --verify --deep --strict --verbose=2 .build/export/Foundry.app
spctl -a -vv .build/export/Foundry.app
```

Отладка отказа: `xcrun notarytool log <submission-id> --keychain-profile notary`.

### 4.3 Sparkle 2: автообновления

- Приложение не sandboxed → **простой путь Sparkle** (без XPC-installer-сервиса и
  temp-exception entitlements).
- Ключи: `./bin/generate_keys` → EdDSA (ed25519). Приватный ключ падает в login
  Keychain — **экспортировать и забэкапить**: потеря ключа стрэндит всех
  пользователей. Публичный — в Info.plist как `SUPublicEDKey`.
- `SUFeedURL` → https-URL appcast'а (GitHub Releases/Pages — бесплатно и достаточно).
- Публикация: собрать/нотарифицировать → `./bin/generate_appcast updates_dir/`
  (пишет EdDSA-подписи и дельты в `appcast.xml`) → залить архив + appcast.
- Формат апдейта: **ZIP** (Sparkle умеет zip/tar/dmg/aar; zip — минимум тулинга,
  тот же файл может служить и первичной загрузкой).

### 4.4 DMG для сайта

Для человеческой загрузки с сайта — подписанный и нотарифицированный **DMG с
симлинком на /Applications** (drag-to-install):

```bash
npx create-dmg .build/export/Foundry.app .build/   # sindresorhus/create-dmg 8.x: zero-config, подписывает DMG
xcrun notarytool submit .build/Foundry*.dmg --keychain-profile notary --wait
xcrun stapler staple .build/Foundry*.dmg           # staple к самому DMG
```

Итого артефактов на релиз два: `Foundry.zip` (Sparkle) + `Foundry.dmg`
(сайт). Допустимое упрощение — только ZIP для обоих, ценой полировки установки.

### 4.5 Homebrew: свой tap

`brew install --cask` — table stakes для dev-тула. Но в основной homebrew/cask
самоподача требует notability (≥225★ / 90 forks / 90 watchers у репо; 75/30/30 при
подаче третьим лицом). До этого порога — **собственный tap**:

- репо `github.com/<you>/homebrew-tap`, файл `Casks/foundry-desktop.rb`;
- установка: `brew install <you>/tap/foundry-desktop`;
- в cask — блок `livecheck`, указывающий на Sparkle-appcast или GitHub Releases;
- бамп version + sha256 — шаг релиз-скрипта (§6).

---

## 5. CI: GitHub Actions

**Раннер:** `macos-26` (GA с февраля 2026, Apple Silicon; дефолтный Xcode — 26.4.x,
при необходимости `sudo xcode-select -s /Applications/Xcode_26.x.app`). Версию
раннера **пиннить** — не `macos-latest`: от неё зависят снапшот-голдены
([глава 07 §4](07-testing-quality.md)). macOS-минуты стоят 10× Linux
($0.062/мин) — держать джобы тонкими; всё, что не требует мака (lint markdown,
скрипты), уводить на Linux.

**SPM-кэш:**

```yaml
- uses: actions/cache@v4
  with:
    path: |
      Packages/FoundryKit/.build
      ~/Library/Caches/org.swift.swiftpm
    key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
```

Кэшировать DerivedData можно (ключ по Package.resolved + pbxproj), выигрыш
скромный — не переусложнять.

**Подпись в CI (только release-workflow).** Developer ID `.p12` — base64 в secret;
в начале джобы — временный keychain:

```bash
security create-keychain -p "$KEYCHAIN_PWD" build.keychain
security default-keychain -s build.keychain
security unlock-keychain -p "$KEYCHAIN_PWD" build.keychain
echo "$CERT_B64" | base64 --decode > cert.p12
security import cert.p12 -k build.keychain -P "$CERT_PWD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PWD" build.keychain
```

Последняя строка **не опциональна**: без `set-key-partition-list` codesign молча
виснет на попытке доступа к ключу — классическое «джоба висит 6 часов и падает по
таймауту».

**Notarization в CI** — через App Store Connect **API key** (`.p8` в secret), не
через Apple-ID + app-specific password:

```bash
xcrun notarytool submit .build/Foundry.zip \
  --key AuthKey.p8 --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" --wait
```

**Разбивка workflow:**

| Workflow | Триггер | Шаги |
|---|---|---|
| `ci.yml` | PR | `swift format lint --strict` → `swift test` (пакет) → `xcodebuild test \| xcbeautify` (без подписи) → отдельная job: контракт-тесты с установленным foundry (`RUN_CONTRACT_TESTS=1`) |
| `release.yml` | `release: published` | archive → export (sign) → notarize → staple → ZIP + DMG → `generate_appcast` → `gh release create` → бамп cask в tap |

**Колонка «Триггер» — фактическая, «Шаги» — целевые.** Триггеры зафиксированы
решением и реализованы:

- CI **не гоняется на push в master** осознанно: macOS-минуты стоят 10× Linux, а
  содержимое PR проверено до мержа. Цена — поломка master всплывёт на следующем
  PR, а не сразу после мержа.
- Релиз собирается **по событию `release: published`**, а не по пушу тега: релиз
  создаёт человек в GitHub, тег заводится там же, отдельный триггер на тег не
  нужен.

Шаги — целевое состояние: notarization, `generate_appcast` и бамп cask появятся
вместе с Developer ID (§4.1–4.3, §4.5). Что реализовано на сегодня и чем это
отличается от канона — в README репозитория.

---

## 6. Версии, changelog, релиз-скрипты

### 6.1 Две версии

- **`MARKETING_VERSION`** → `CFBundleShortVersionString` (человеческая, `1.4.0`).
- **`CURRENT_PROJECT_VERSION`** → `CFBundleVersion` (build number). Sparkle
  сравнивает именно её — обязана **монотонно расти** между релизами. Простая
  схема: `git rev-list --count HEAD`.

Выставление из CLI, не трогая pbxproj (наш выбор — overrides при архивировании):

```bash
xcodebuild archive \
  MARKETING_VERSION=1.4.0 \
  CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD) \
  ...
```

Альтернатива — `xcrun agvtool new-marketing-version 1.4.0` (пишет в pbxproj; тоже
легально, но мы держим pbxproj неизменным — см. §1.1).

### 6.2 Changelog

`CHANGELOG.md` в формате [Keep a Changelog](https://keepachangelog.com); агент
дописывает секцию `[Unreleased]` в каждом содержательном PR. Релиз-скрипт
извлекает секцию версии в тело GitHub Release и в `<description>` appcast'а
(или `sparkle:releaseNotesLink` на HTML). Теги — `v1.4.0`.

### 6.3 Релиз — plain-скрипты, не fastlane

⚠️ **fastlane для non-MAS macOS — лишний слой**: его ценность сконцентрирована в
iOS-provisioning и App Store-боли, которых у нас нет; взамен он приносит Ruby-стек
и DSL, который агенту сложнее отлаживать, чем прямые CLI-вызовы. Консенсус
2025–2026 для этой формы проекта — Makefile/justfile:

```just
# justfile (фрагмент)
release version:
    just test
    xcodebuild archive -project Foundry.xcodeproj -scheme Foundry \
      -destination 'platform=macOS' -archivePath .build/Foundry.xcarchive \
      MARKETING_VERSION={{version}} CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)
    xcodebuild -exportArchive -archivePath .build/Foundry.xcarchive \
      -exportOptionsPlist scripts/ExportOptions.plist -exportPath .build/export
    ditto -c -k --keepParent .build/export/Foundry.app .build/Foundry.zip
    xcrun notarytool submit .build/Foundry.zip --keychain-profile notary --wait
    xcrun stapler staple .build/export/Foundry.app
    npx create-dmg .build/export/Foundry.app .build/
    ./scripts/sparkle/generate_appcast .build/updates
    gh release create v{{version}} .build/Foundry.zip .build/*.dmg \
      --notes "$(./scripts/changelog-extract.sh {{version}})"
    ./scripts/bump-tap.sh {{version}}
```

Каждый шаг — обычный CLI, который агент может запустить, увидеть ошибку и починить.

---

## Чеклист ревью

- [ ] Оба `Package.resolved` (пакетный и проектный) закоммичены; их изменение —
      отдельный осознанный коммит.
- [ ] Новая зависимость обоснована в PR; статус сопровождения проверен; 0.x-пакеты
      запинены `.upToNextMinor`; Splash не появился.
- [ ] pbxproj не изменился (или изменение объяснено: новый таргет/capability —
      не добавление файлов).
- [ ] Новые файлы легли в правильный таргет пакета; направление зависимостей
      модулей не нарушено (Core ни от чего не зависит).
- [ ] Entitlements не разбухли: каждый новый ключ — с обоснованием; App Sandbox
      по-прежнему выключен осознанно (глава 06).
- [ ] `swift test` в пакете и `xcodebuild test` проходят локально;
      `set -o pipefail` присутствует во всех пайпах с xcbeautify.
- [ ] Релизный артефакт: `CFBundleVersion` вырос монотонно; ZIP и DMG
      нотарифицированы и застейплены; `spctl -a -vv` зелёный.
- [ ] Appcast сгенерирован `generate_appcast`, EdDSA-ключ не менялся; приватный
      ключ забэкаплен вне машины.
- [ ] `CHANGELOG.md` обновлён (секция Unreleased → версия); cask в tap бампнут.
- [ ] CI: версия раннера запинена (`macos-26`, не latest); секреты не светятся в
      логах; временный keychain с `set-key-partition-list`.

## Источники

- Buildable folders / pbxproj — https://blog.makwanbk.com/how-one-new-xcode-feature-helped-my-work-project-eliminate-66k-lines-of-code, https://tuist.dev/blog/2025/03/21/git-conflicts
- Локальные пакеты — https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages, https://philprime.dev/blog/2021/04/12/modularize-xcode-projects-using-local-swift-packages.html
- Tuist vs XcodeGen — https://medium.com/@sayefeddineh/xcodegen-vs-tuist-choosing-the-right-tool-for-xcode-project-generation-bea093c6e105, https://www.runway.team/blog/xcode-project-generation
- swift-bundler — https://swiftbundler.dev/
- xcodebuild — https://developer.apple.com/library/archive/technotes/tn2339/_index.html, https://danfabulich.medium.com/xcodebuild-cli-cheat-sheet-b7ee7b3d5fc6
- xcbeautify — https://github.com/cpisciotta/xcbeautify
- Notarization — https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution, https://developer.apple.com/documentation/security/customizing-the-notarization-workflow, https://developer.apple.com/developer-id/
- Порядок подписи / Sparkle в бандле — https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5
- Sparkle — https://sparkle-project.org/documentation/, https://sparkle-project.org/documentation/publishing/, https://hobbyworker.me/en/dev/2026-05-15-distribute-macos-app-2-sparkle-signing-key/
- create-dmg — https://github.com/sindresorhus/create-dmg
- Homebrew Acceptable Casks — https://docs.brew.sh/Acceptable-Casks
- GitHub Actions macOS — https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/, https://docs.github.com/en/billing/reference/actions-runner-pricing
- Подпись в CI — https://federicoterzi.com/blog/automatic-code-signing-and-notarization-for-macos-apps-using-github-actions/, https://www.codejam.info/2025/06/github-action-hanging-macos-app-code-signing.html
- Changelog — https://keepachangelog.com
- fastlane — https://fastlane.tools/
