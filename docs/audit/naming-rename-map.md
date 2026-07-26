# Карта переименований — foundry-desktop

Итог по 6 зонам (Core+CLI, Features-core, Orb+Bench, Onboarding-flow, Onboarding-visual, Tests).

**Всего предложений: 96**

По severity:
- **bad: 8**
- **mediocre: 52**
- **nit: 36**

По kind:
- property: 44
- local: 18
- func: 10
- parameter: 10
- type: 8
- testName: 3
- enumCase: 1
- file: 1
- label: 1

Инвариант: строковые ЗНАЧЕНИЯ не меняются (JSON-ключ `"cwd"`, UserDefaults `"openInClaudeDesktop"`, AppStorage `"didFinishOnboarding"`, .metal имена функций `swarmPostVertex/Fragment`, `@Suite("FoundryCore")` display-string — всё остаётся). Переименовываются только Swift-символы.

---

## Сквозные соглашения

Соглашения к применению по всему проекту (в скобках — победитель при конфликте между зонами):

- **Рабочая директория запуска — одно слово `projectDirectory`.** Убить три написания одного значения: `cwd` (SessionInit, openSession, JSON-чтение), `workingDirectory` (внешний Subprocess API — НЕ трогать), победитель — `projectDirectory` (уже используется в ClaudeStreaming/ClaudeRunner). JSON-ключ `"cwd"` в декодере остаётся.
- **Фабрики значений — глагол `make…`.** `buildArguments → makeArguments` (рядом `makePlatformOptions`), локальные `fn → makeFunction`/`loadFunction`.
- **Миллисекунды — полное слово.** `millis`/`MS` → `milliseconds` (production-символы: `RunResult.durationMS`, `RunFormat.duration(millis:)`). Cross-target.
- **Claude Desktop пишем полностью, без CCD.** `openInCCDKey → openInClaudeDesktopKey`, `ccdToggle → claudeDesktopToggle`. Строка-ключ `"openInClaudeDesktop"` не меняется.
- **Идентификатор сессии — `sessionID`.** Унифицировать label параметра в ClaudeDesktopLink (`id → sessionID` в openSession/openSessionWhenTranscriptExists), как в transcriptPath и RunResult.sessionID.
- **Расширения (browser extensions) — полное слово `extension(s)`.** Убить `ext`-клип: `exts → extensions`, `installedExts → installedExtensions`, `installingExt → installingExtension`, `tapExt → tapExtension` (сиблинги `agents`/`tapAgent` уже полные). Источник — `OnboardingCatalog.extensions`.
- **Описательная строка — `description`.** Убить `desc`: `Setting.desc`, `Permission.desc`, `SettingRow.desc → description`. (Сиблинги `requirement`/`installedDetail`/`signedInLabel` остаются как есть — победитель для безымянного «второго текста» = `description`.)
- **Булевы читаются как утверждения — `is/has/did/should/draws…`.** `pulsing→isPulsing`, `hovering→isHovering`, `on→isOn`, `granted→isGranted`, `animating→isAnimating`, `bursting→isBursting`, `positioned→didPositionWindow`, `onboarding→isOnboarding`, `solo→isStandalone`, `done→didFinishOnboarding`, `burstT0Set→didFreezeBurstTime`, `reduceMotion→shouldReduceMotion`, `drawLines→drawsTrails`. Уже верные (`showsInstall`, `didReveal`, `isTitlebar`, `selected`, `passed`) не трогать.
- **`window` пишем полностью.** `winOpacity→windowOpacity`, `winScale→windowScale`.
- **Точки/размер точки — `pointSize`, не `pt`/`pointScreen`.** `pt`(поле/локаль)→`pointSize`, `pointScreen`→`pointSizeOnScreen`. ВНИМАНИЕ: `pt(_:_:)` — CGPoint-фабрика в OnboardingGlyphs/Buttons — это ДРУГОЙ концепт; её оставить (или → `point`), размер точки нельзя называть тем же `pt`.
- **Supersample / resolution пишем полностью.** `ss→supersample`, `res→resolution` (в Swift; байт-layout .metal не зависит от имени поля).
- **Второй проход рендера — одно слово `resolve`, не `post`.** `postPipeline→resolvePipeline`, `postDesc→resolveDesc`, `postEnc/postPass` → `resolve…`. Строки шейдер-функций `swarmPostVertex/Fragment`, `postVertex/postFragment` — .metal имена, остаются.
- **Первый проход (Orb) — одно слово `particle`, не `orb`.** `orbPipeline→particlePipeline`, `orbDesc/orbEnc → particle…`. `OrbUniforms`/`orbVertex` — отдельная шейдерная ось, остаются.
- **Буфер частиц — `bufferWidth/bufferHeight` (не `bufW/bufH`), пиксельные стороны несут суффикс `…Side`.** `buffer→bufferSide`, `output→outputSide`, `count→particleCount`.
- **`config`, не `cfg`.** Единое написание локалей по всем зонам (OrbSwarmView.configure, OrbBench, тесты).
- **`observer`, не `obs`.** Один наблюдатель во всех методах WindowConfigurator.
- **Имя файла = имя главного типа.** `OnboardingWindowConfigurator.swift` держит тип `WindowConfigurator` (тип обслуживает и не-онбординг окно) → переименовать ФАЙЛ в `WindowConfigurator.swift`.
- **Пагинация симметрична — `goNext`/`goPrevious`.** `goPrev→goPrevious`.
- **Никаких 1–2-символьных несёрчабельных имён вне крошечного цикла.** `u→uniforms`, `r→resolveUniforms/renderer`, `d→outDesc`, `s/w→text/width`, `v→containerView`, `p→progress/permission`, `s→setting/labelSize`, `vf→visibleFrame`, `cls→className`.
- **Имена типов — доменные существительные, не noise/keyword.** `Case→BenchmarkCase`, `SessionInit→SessionStart`, `KeyCatcher→ArrowKeyMonitor`, `GCDOnboardingScheduler→MainQueueOnboardingScheduler` (не кодировать GCD), `OBSub→OBSubtitle`.
- **Тестовые имена раскрывают проверяемое поведение.** `result→resultEventBecomesFinished`, `tolerance→unknownAndUnparsableDoNotCrashRun`, `transcriptPathMunging→transcriptPathReplacesPathSeparators`.

Разрешённые конфликты между зонами:
- Концепт «второй текст под заголовком»: Onboarding-flow и Onboarding-visual оба предлагали `desc→description` — единый победитель `description` (не `detail`).
- `pt` фигурирует в Orb+Bench, Onboarding-visual (размер точки → `pointSize`) и как CGPoint-фабрика — размер точки унифицируется на `pointSize`, фабрика `pt(_:_:)` остаётся отдельным именем.
- `bursting→isBursting` предложен и в Features-core (OrbView оговорка) и в Onboarding-visual — одна запись, две площадки.

---

## Переименования по зонам

### Core+CLI

| current → proposed | kind | location | severity | risk |
|---|---|---|---|---|
| `buildArguments → makeArguments` | func | ClaudeRunner.swift · static buildArguments(prompt:permissionMode:) L57, call L110 | mediocre | none (private static, один call site) |
| `cwd → projectDirectory` | parameter | ClaudeSessionOpening.swift · openSession(id:cwd:) L10 | mediocre | cross-target / public-API — public protocol, адаптер ClaudeDesktopSessionOpener; обновить conformance + call site |
| `cwd → projectDirectory` | property | ClaudeEvent.swift · SessionInit.cwd (L25,30); строится в ClaudeEventDecoder.decodeSystem L77 | nit | cross-target / test-visible — читается RunStore/feed UI; JSON-ключ `"cwd"` НЕ меняется |
| `SessionInit → SessionStart` | type | ClaudeEvent.swift · struct SessionInit L22; payload case sessionStarted L5; decodeSystem L73 | nit | cross-target / test-visible — decoder + RunStore/tests |
| `fm → fileManager` | local | ClaudeRunner.swift · locateClaude() L41, исп. 42,52 | mediocre | none (function-local) |
| `path → environmentPath` | local | ClaudeRunner.swift · stream(...) L112, исп. 118 | mediocre | none (function-local) |
| `override → overridePath` | local | ClaudeRunner.swift · locateClaude() L49, исп. 50 | nit | none (function-local) |

### Features-core

| current → proposed | kind | location | severity | risk |
|---|---|---|---|---|
| `detail → toolResult` | property | RunStore.swift · FeedItem.detail (public var) | mediocre | public / test-visible — grep FeedItem(...).detail, feed[i].detail в RunStore + FeedItemView |
| `millis → milliseconds` | parameter | RunPresentation.swift · RunFormat.duration(millis:) | mediocre | test-visible — call в FeedViews.swift + тест; см. унификацию с durationMS |
| `munged → escapedCwd` | local | ClaudeDesktopLink.swift · transcriptPath(sessionID:cwd:) | bad | none — function-local |
| `openInCCDKey → openInClaudeDesktopKey` | property | RunStore.swift · openInCCDKey (private static let) | nit | none — строка UserDefaults не трогается |
| `ccdToggle → claudeDesktopToggle` | property | RunConsoleView.swift · ccdToggle (private computed) | nit | none — private |
| `pulsing → isPulsing` | property | OrbView.swift · OrbView.pulsing (@State) | nit | none — private |
| `hovering → isHovering` | parameter | Motion.swift · AppMotion.hover(_ hovering: Bool) | nit | none — label `_`, только тело |

### Orb+Bench

| current → proposed | kind | location | severity | risk |
|---|---|---|---|---|
| `buffer → bufferSide` | property | OrbSwarmConfig.swift · buffer (public let, L111) | bad | cross-target/public — OrbSwarmRenderer (update/allocateTextures/encodeParticlePass), OrbBench main.swift |
| `orb → orbBodyFraction` | property | OrbSwarmConfig.swift · static let orb (L11) | bad | internal — Self.orb в этом файле |
| `output → outputSide` | property | OrbSwarmConfig.swift · output (public let, L107) | mediocre | cross-target/public — OrbSwarmView.configure, OrbBench |
| `grainLoader → loaderGrain` | property | OrbSwarmConfig.swift · static let grainLoader (L18) | mediocre | internal — Self.grainLoader в coverage |
| `pointScreen → pointSizeOnScreen` | property | OrbSwarmConfig.swift · Loader.pointScreen (L67) + init param (L148) | mediocre | none — internal Loader member |
| `steps → stutters` | func | OrbSwarmConfig.swift · static steps(preset:displayHz:)->Bool (L230) | mediocre | test-visible — OrbSwarmView.applyFrameRate assert; public |
| `count → particleCount` | property | OrbSwarmConfig.swift · count (public let, L114) | nit | cross-target/public — OrbSwarmRenderer.encodeParticlePass, OrbBench |
| `ss → supersample` | property | OrbSwarmRenderer.swift · ResolveUniforms.ss (L26) | mediocre | none — зеркалит OrbSwarm.metal; Swift+shader вместе |
| `pt → pointSize` | property | OrbSwarmRenderer.swift · OrbUniforms.pt (L20) | mediocre | none — зеркалит OrbSwarm.metal; Swift+shader вместе |
| `res → resolution` | property | OrbSwarmRenderer.swift · OrbUniforms.res (L18) | nit | none — зеркалит OrbSwarm.metal |
| `noLibrary → resourceMissing` | enumCase | OrbSwarmRenderer.swift · SetupError.noLibrary (L30); misuse L57,88 | mediocre | public-API — SetupError public |
| `postPipeline → resolvePipeline` | property | OrbSwarmRenderer.swift · postPipeline L46 (+postDesc 79, postEnc 200, postPass 195) | mediocre | none — internal |
| `orbPipeline → particlePipeline` | property | OrbSwarmRenderer.swift · orbPipeline L45 (+orbDesc 68, orbEnc 175) | nit | none — internal |
| `u → uniforms` | local | OrbSwarmRenderer.swift · encodeParticlePass L176 | mediocre | none |
| `r → resolveUniforms` | local | OrbSwarmRenderer.swift · encodeResolvePass L201 | mediocre | none |
| `fn → makeFunction` | func | OrbSwarmRenderer.swift · local func fn(_:) init L63 | nit | none |
| `frozen → frozenTime` | property | OrbSwarmView.swift · Coordinator.frozen (L92) | mediocre | none — private |
| `start → startTime` | property | OrbSwarmView.swift · Coordinator.start (L89) | nit | none — private |
| `Case → BenchmarkCase` | type | OrbBench/main.swift · struct Case (L11) | mediocre | none — script-local; массив `cases`, loop `c` вместе |
| `rpad → padLeading` | func | OrbBench/main.swift · rpad(_:_:) (L56) | mediocre | none — script-local |
| `pad → padTrailing` | func | OrbBench/main.swift · pad(_:_:) (L53) | nit | none — script-local |
| `s → text` | parameter | OrbBench/main.swift · pad/rpad param s (L53,56) | nit | none |
| `w → width` | parameter | OrbBench/main.swift · pad/rpad param w (L53,56) | nit | none |
| `r → renderer` | local | OrbBench/main.swift · --dump/--loaders loops (L121,165) | mediocre | none |
| `d → outDesc` | local | OrbBench/main.swift · --dump/--loaders loops (L122,166) | mediocre | none |

### Onboarding-flow

| current → proposed | kind | location | severity | risk |
|---|---|---|---|---|
| `done → didFinishOnboarding` | property | OnboardingContainer.swift · FoundryRootView.done (L8) | bad | none — private; AppStorage-ключ уже "didFinishOnboarding" |
| `exts → extensions` | property | OnboardingModel.swift · exts (L28) | bad | none — internal; из OnboardingCatalog.extensions |
| `winOpacity → windowOpacity` | property | OnboardingContainer.swift · FoundryRootView (L9) | mediocre | none — private |
| `winScale → windowScale` | property | OnboardingContainer.swift · FoundryRootView (L10) | mediocre | none — private |
| `installedExts → installedExtensions` | property | OnboardingModel.swift (L29) | mediocre | test-visible — ExtensionsScreen; проверить onboarding-тесты |
| `installingExt → installingExtension` | property | OnboardingModel.swift (L30) | mediocre | none — internal |
| `tapExt → tapExtension` | func | OnboardingModel.swift · tapExt(_:) (L180) | mediocre | test-visible — ExtensionsScreen; вероятно в тестах |
| `desc → description` | property | OnboardingModel.swift · Setting.desc (L36), Permission.desc (L51) | mediocre | none — struct-local; SettingRow(desc:) label независим |
| `on → isOn` | property | OnboardingModel.swift · Setting.on (L37) | mediocre | none — OBToggle(on:) независим |
| `granted → isGranted` | property | OnboardingModel.swift · Permission.granted (L52) | mediocre | none — GrantButton(granted:) независим |
| `screenPadBottom → screenBottomPadding` | property | OnboardingModel.swift (L79) | mediocre | none — OnboardingContainer.stageRegion |
| `goPrev → goPrevious` | func | OnboardingModel.swift · goPrev() (L157) | mediocre | none — KeyCatcher onLeft |
| `p → progress` | parameter | OnboardingModel.swift · burstProgress(_ p:) (L218) | mediocre | none — trailing-closure call не задет |
| `OBSub → OBSubtitle` | type | OnboardingScreens.swift · OBSub (L19) | mediocre | none — private |
| `solo → isStandalone` | parameter | OnboardingScreens.swift · OBTitle.solo (L6) | mediocre | none — один call site |
| `afterDelay(_:_:) → schedule(after:_:)` | func | OnboardingScheduler.swift · protocol L14 + GCDOnboardingScheduler L20 | mediocre | test-visible — manual test scheduler + 4 call sites в OnboardingModel |
| `GCDOnboardingScheduler → MainQueueOnboardingScheduler` | type | OnboardingScheduler.swift (L19) | mediocre | none — default в OnboardingModel.init |
| `OnboardingWindowConfigurator.swift → WindowConfigurator.swift` (файл) | file | OnboardingWindowConfigurator.swift · struct WindowConfigurator (L9) | mediocre | none — только rename файла, тип не двигается |
| `onboarding → isOnboarding` | property | OnboardingWindowConfigurator.swift · WindowConfigurator.onboarding (L10) | mediocre | none — один call site |
| `animating → isAnimating` | property | OnboardingModel.swift (L19) | nit | none — private(set) |
| `bursting → isBursting` | property | OnboardingModel.swift (L61) | nit | test-visible — footer + tapAgent/tapExt guards |
| `KeyCatcher → ArrowKeyMonitor` | type | OnboardingContainer.swift · KeyCatcher (L186) | nit | none — private, один call site |
| `hovering → isHovering` | property | OnboardingContainer.swift · SkipButton (L222) | nit | none — private |
| `dest → destination` | local | OnboardingModel.swift · startTransition() (L127) | nit | none — local |
| `s → setting` | local | OnboardingScreens.swift · SettingsScreen ForEach (L102) | nit | none — loop-local |
| `p → permission` | local | OnboardingScreens.swift · PermissionsScreen ForEach (L127) | nit | none — loop-local |
| `rows: [(String,String)] → [(label:String, detail:String)]` | property | OnboardingScreens.swift · ReadyScreen.rows (L148) | nit | none — private; row.0/row.1 в теле |
| `positioned → didPositionWindow` | property | OnboardingWindowConfigurator.swift · Coordinator (L13) | nit | none — Coordinator-private |
| `vf → visibleFrame` | local | OnboardingWindowConfigurator.swift · centerTop() (L276) | nit | none — local |
| `cls → className` | local | OnboardingWindowConfigurator.swift · setTitlebarChromeHidden walk() (L259) | nit | none — local |
| `obs → observer` | local | OnboardingWindowConfigurator.swift · installChromeEnforcement() (L126) | nit | none — local |
| `v → containerView` | local | OnboardingWindowConfigurator.swift makeNSView (L35) + OnboardingContainer.swift KeyCatcher.makeNSView (L192) | nit | none — locals |

### Onboarding-visual

| current → proposed | kind | location | severity | risk |
|---|---|---|---|---|
| `pt → pointSize` | property | OnboardingSwarmView.swift · Coordinator.pt (L92; assign 175, read 244) | bad | none — private to Coordinator |
| `fi → fractionalIndex` | property | OnboardingDots.swift · LiquidBlob.fi (L89); call L74 | bad | none — internal Shape; один call site |
| `jit → jitter` | property | OnboardingSwarmRenderer.swift · SwarmUniforms.jit (L37; set 203,215) | bad | internal — loop var уже `jitter` (L212) |
| `ss → supersample` | property | OnboardingSwarmRenderer.swift · ResolveUniforms.ss (L42) | bad | internal — ctor arg уже `supersample:` (L237) |
| `pt → pointSize` | property | OnboardingSwarmRenderer.swift · SwarmUniforms.pt (L27) | mediocre | internal — с Coordinator write (u.pt) вместе |
| `res → resolution` | property | OnboardingSwarmRenderer.swift · SwarmUniforms.res (L26) | mediocre | internal — зеркалит shader |
| `bufW / bufH → bufferWidth / bufferHeight` | property | OnboardingSwarmRenderer.swift (L68-69, resize 133) + OnboardingSwarmView.Coordinator (L91) | mediocre | multi-site, internal к этим файлам |
| `bursting → isBursting` | property | OnboardingSwarmView.swift · view.bursting (L13) + Coordinator.bursting (L98) | mediocre | internal — updateNSView/setBursting/draw |
| `burstT0Set → didFreezeBurstTime` | property | OnboardingSwarmView.swift · Coordinator.burstT0Set (L102) | mediocre | none — private |
| `reduceMotion → shouldReduceMotion` | property | OnboardingSwarmView.swift · Coordinator.reduceMotion computed (L103) | mediocre | none — private computed |
| `recompute → recomputeLayout` | func | OnboardingSwarmView.swift · Coordinator.recompute(view:pixelSize:) (L163) | mediocre | none — private, 2 call sites |
| `drawLines → drawsTrails` | parameter | OnboardingSwarmRenderer.swift · encode(…drawLines:) L160 + encodeParticlePass L178; local в draw L200 | mediocre | internal к двум файлам; param+local+call site вместе |
| `lineVerts → lineVertexCount` | local | OnboardingSwarmRenderer.swift · encodeParticlePass (L211) | mediocre | none — local |
| `postPipeline → resolvePipeline` | property | OnboardingSwarmRenderer.swift (L62; build 96) | mediocre | internal; shader strings swarmPostVertex/Fragment остаются |
| `postDesc → resolveDesc` | local | OnboardingSwarmRenderer.swift · init (L92) | mediocre | none — local |
| `segs → segments` | property | OnboardingSwarmRenderer.swift · static segs (L46) | mediocre | internal — исп. L211 |
| `desc → description` | property | OnboardingSetPanel.swift · SettingRow.desc (L39) | mediocre | internal — SettingRow call sites в screens |
| `kbd → shortcutKey` | property | OnboardingButtons.swift · OBPrimaryButton.kbd (L46; use 47) | mediocre | internal — OBPrimaryButton(kbd:) call sites |
| `amp → amplitude` | property | OnboardingBackdrop.swift · OBNoise.amp (L12; use 27,31) | mediocre | none — enum-scoped |
| `easeReal(_ d:) → easeReal(_ duration:)` | parameter | OnboardingStyle.swift · OB.easeReal (L46) | mediocre | none — label unlabeled |
| `s → labelSize` | local | OnboardingWordmark.swift · aiLabel let s (L27) | mediocre | none — local |
| `bottomPad → bottomPadding` | property | OnboardingDots.swift · static (L29) + mirror (L37) + DotSlot.bottomPad (L160) | nit | none — в пределах файла |
| `current → currentIndex` | property | OnboardingDots.swift · OnboardingDots.current (L13) | nit | none — OnboardingDots(current:) call sites |
| `rnd → nextRandom` | func | OnboardingBackdrop.swift · local func rnd() (L20) | nit | none — local func |
| `fn → loadFunction` | func | OnboardingSwarmRenderer.swift · local func fn(_:) (L79) | nit | none — local, 4 call sites |
| `depthWrite / depthNoWrite → depthWriteState / depthReadOnlyState` | property | OnboardingSwarmRenderer.swift (L63-64) | nit | none — private |
| `r (label) → radius` | label | OnboardingGlyphs.swift · appendSVGArc(…r radius…) (L14) | nit | none — 8 call sites |
| `headP / tailP → headProgress / tailProgress` | local | OnboardingDots.swift · LiquidBlob.path(in:) (L108-109) | nit | none — locals |
| `OBCard → AgentCardModel` | type | OnboardingAgentCard.swift · struct OBCard (L8) | nit | test-visible? возможно — конструируется экраном-декой; флаг call sites |

### Tests

| current → proposed | kind | location | severity | risk |
|---|---|---|---|---|
| `result → resultEventBecomesFinished` | testName | ClaudeEventDecoderTests.swift:66 (func result) | bad | test-visible only |
| `FoundryCoreTests → PermissionModeTests` | type | PermissionModeTests.swift:5 (struct) | mediocre | test-visible; @Suite("FoundryCore") display-string НЕ трогается |
| `tolerance → unknownAndUnparsableDoNotCrashRun` | testName | ClaudeEventDecoderTests.swift:84 | mediocre | test-visible only |
| `transcriptPathMunging → transcriptPathReplacesPathSeparators` | testName | ClaudeDesktopLinkTests.swift:9 | mediocre | test-visible only |
| `s / f → standardFloor / fineFloor` | local | OrbSwarmConfigTests.swift:194-195 | mediocre | none |
| `n → particleCount` | local | OrbSwarmConfigTests.swift:18 | nit | none |
| `at1 / at2 → atScale1 / atScale2` | local | OrbSwarmConfigTests.swift:46-47 | nit | none |
| `l32 / l64 → loader32 / loader64` | local | OrbSwarmConfigTests.swift:110-111 | nit | none |
| `cfg → config` | local | OrbSwarmConfigTests.swift:37,80,85,166 | nit | none |
| `infos → infoItems` | local | RunStoreTests.swift:131 | nit | none |

---

## Несогласованности → унификация

| Концепт | Написания в коде | Победитель | Cross-target? |
|---|---|---|---|
| Рабочая директория запуска | `projectDirectory` / `cwd` / `workingDirectory`(внешн.) | **`projectDirectory`** (JSON-ключ `"cwd"` остаётся; Subprocess `workingDirectory` не трогать) | да — public protocol + decoder + RunStore |
| Фабрика значения | `makePlatformOptions` / `buildArguments` | **`make…`** → `makeArguments` | нет |
| Миллисекунды | `RunResult.durationMS` / `RunFormat.duration(millis:)` | **`milliseconds`** (`durationMilliseconds`) | да — production, FeedViews + тесты |
| Claude Code Desktop | `openInClaudeDesktop`(prop/строка) / `openInCCDKey` / `ccdToggle` | **spelled-out** → `…ClaudeDesktopKey`, `claudeDesktopToggle` (строка не меняется) | нет |
| Идентификатор сессии (label) | `id` (openSession/…) / `sessionID` (transcriptPath, RunResult) | **`sessionID`** | внутри ClaudeDesktopLink |
| Расширения браузера | `exts`/`installedExts`/`installingExt`/`tapExt` / `extensions`(Catalog) | **`extension(s)`** полностью | да — прод-символы + onboarding-тесты |
| «Второй текст» под заголовком | `desc` (Setting/Permission/SettingRow) / `requirement`,`installedDetail`,`signedInLabel` | **`description`** (не `detail`) | нет (struct-local) |
| Булев флаг | assertion-формы vs `bursting`,`reduceMotion`,`burstT0Set`,`drawLines`,`on`,`granted`,`done`,`positioned`,`onboarding`,`solo`,`animating`,`hovering`,`pulsing` | **`is/has/did/should/draws…`** | нет |
| Окно | `win…` (winOpacity/winScale) / `window…`(NSWindow,WindowConfigurator) | **`window`** | нет |
| Размер точки | `pt`(поле/локаль) / `pointScreen` / `pointSize`,`pointSizeOnScreen`(config) | **`pointSize` / `pointSizeOnScreen`**; CGPoint-фабрика `pt(_:_:)` — отдельно | Swift+.metal вместе |
| Supersample | `supersample`(config/ctor) / `ss`(ResolveUniforms×2) | **`supersample`** | Swift+.metal вместе |
| Resolution | `resolution` / `res` | **`resolution`** | Swift+.metal |
| Проход рендера #2 | `resolve`(encodeResolvePass,ResolveUniforms) / `post`(pipeline/desc/enc/pass) | **`resolve`** (шейдер-строки `…PostVertex/Fragment` остаются) | нет |
| Проход рендера #1 | `particle`(encodeParticlePass) / `orb`(pipeline/desc/enc) | **`particle`** (`OrbUniforms`/`orbVertex` — шейдер-ось, остаются) | нет |
| Буфер частиц | `bufW/bufH` / `bufferWidth/bufferHeight` | **`bufferWidth`/`bufferHeight`** | нет (в пределах файлов) |
| Пиксельные стороны | `buffer`,`output`(голые сущ.) / `pointSize`,`count`(role-named) | **несут суффикс `…Side`** → `bufferSide`,`outputSide`; `count`→`particleCount` | да — public config |
| config-локаль | `cfg` / `config` | **`config`** | нет |
| Наблюдатель уведомлений | `obs` / `observer` | **`observer`** | нет |
| Имя файла vs тип | `OnboardingWindowConfigurator.swift` / `WindowConfigurator` | **файл → `WindowConfigurator.swift`** (тип держит и не-онбординг окно) | нет |
| Пагинация | `goNext`(полн.) / `goPrev`(сокр.) | **`goPrevious`** | нет |
| Модель/вью карточки | `AgentCard`(view) / `OBCard`(model) | **одна семья** → `AgentCardModel`/`AgentCard` | флаг call sites-деки |
| Два типа «Orb» | `OrbView`(22pt статус) / `OrbSwarmView`(поле частиц) | оставить (различие по суффиксу намеренно) — только флаг | нет |
| 1-символьные несёрчабельные | `u,r,d,s,w,v,p,c,n,s/f,at1/at2,l32/l64` | role-имена (см. таблицы зон) | нет |

---

## Порядок применения

Применять «изнутри наружу» — сперва невидимое снаружи, потом тесты, потом публичное/кросс-таргетное.

**Фаза 1 — private / local / внутрифайловое (риск none, начинать здесь).**
Все `local`/`parameter`/приватные `property` без cross-target пометки: Core+CLI (`fm`,`path`,`override`); Features-core (`munged`,`pulsing`,`hovering`,`ccdToggle`,`openInCCDKey`); Orb+Bench internal-локали и приватные Coordinator-поля (`u`,`r`,`d`,`fn`,`frozen`,`start`,`postPipeline`,`orbPipeline`,`Case`,`pad/rpad`,`s`,`w`); весь Onboarding-visual (всё internal/private к файлам роя/точек/панелей); Onboarding-flow приватные (`winOpacity`,`winScale`,`done`,`dest`,`vf`,`cls`,`obs`,`v`,`OBSub`,`solo`,`KeyCatcher`,`positioned`, booleans). Компилировать после каждого файла — переименования локальны, пиксель-нейтральны.

**Фаза 1b — rename файла.** `OnboardingWindowConfigurator.swift → WindowConfigurator.swift` (тип не двигается → call sites целы; обновить membership в проекте).

**Фаза 2 — Swift↔.metal парные поля.** Переименовывать Swift-поле и одноимённое поле в `OrbSwarm.metal`/`OnboardingSwarm.metal` ОДНОВРЕМЕННО (байт-layout не зависит от имени, но парность держать): `ss→supersample`, `pt→pointSize`, `res→resolution`, `jit→jitter`, `segs→segments`, `bufW/bufH→bufferWidth/bufferHeight`, `postPipeline→resolvePipeline`. Шейдер-СТРОКИ функций (`swarmPostVertex/Fragment`, `postVertex/postFragment`, `orbVertex`) НЕ трогать.

**Фаза 3 — имена тестов и тест-локали (test-visible, без прод-символов).** `result`, `tolerance`, `transcriptPathMunging`, `FoundryCoreTests→PermissionModeTests` (display-string `@Suite("FoundryCore")` оставить), `s/f`,`n`,`at1/at2`,`l32/l64`,`cfg→config`,`infos`. Прогнать сьют.

**Фаза 4 — public / cross-target (по одному, компиляция после каждого).**

Трогают **App / RunStore / feed UI**:
- `cwd → projectDirectory` (ClaudeSessionOpening public protocol + адаптер ClaudeDesktopSessionOpener + SessionInit property + decodeSystem; JSON-ключ `"cwd"` СОХРАНИТЬ).
- `SessionInit → SessionStart` (decoder + RunStore + tests).
- `detail → toolResult` (FeedItem public struct; RunStore + FeedItemView).
- `millis → milliseconds` + унификация с `durationMS` (RunFormat + FeedViews + тесты) — прод-символ, cross-target.
- `openInCCDKey`/`ccdToggle` (строки не меняются, но публичны в фичах).
- `exts/installedExts/installingExt/tapExt → extension(s)` (ExtensionsScreen + onboarding-тесты).
- `afterDelay → schedule(after:)` + `GCDOnboardingScheduler → MainQueueOnboardingScheduler` (protocol + manual test scheduler + 4 call sites OnboardingModel).
- `bursting → isBursting`, `installedExtensions`, `tapExtension` — читаются экранами/футером/тестами онбординга.
- `onboarding → isOnboarding` (call site в FoundryRootView).
- `OBCard → AgentCardModel` (флаг: экран, строящий деку).

Трогают **OrbBench** (отдельный таргет) + Renderer:
- `buffer → bufferSide`, `output → outputSide`, `count → particleCount` (public OrbSwarmConfig; OrbSwarmRenderer update/allocateTextures/encodeParticlePass, OrbSwarmView.configure, OrbBench main.swift).
- `steps → stutters` (public; OrbSwarmView.applyFrameRate assert).
- `noLibrary → resourceMissing` (public SetupError).
- OrbBench script-локали (`r→renderer`, `d→outDesc`, `Case→BenchmarkCase`, `pad/rpad`) — уже в Фазе 1, но пересобрать таргет OrbBench.

После Фазы 4 — полный build обоих таргетов (App + OrbBench) и весь тест-сьют; инвариант — ноль визуальных изменений.
