import AppKit
import Core
import SwiftUI

// MARK: - Конфигуратор окна

/// Приводит NSWindow к нужному виду: на онбординге — фиксированное портретное
/// окно 720×880 с прозрачным титлбаром «Foundry — Setup»; после — обычное
/// изменяемое окно «Foundry».
struct WindowConfigurator: NSViewRepresentable {
    let isOnboarding: Bool
    /// Идёт ли мастер ПРЯМО СЕЙЧАС — спрашивается у настроек в момент вызова, а не
    /// берётся из `isOnboarding`. Разница принципиальная для наблюдателей окна
    /// (`installFrameLock`): они переживают конец мастера, а замкнутый в них
    /// `isOnboarding` навсегда остался бы `true` — и главное окно осталось бы
    /// намертво 720×880. Замыкание же держит стор и всегда отвечает по факту.
    let isOnboardingNow: @MainActor () -> Bool

    final class Coordinator {
        var didPositionWindow = false
        // Наблюдатели за сменой фокуса окна: AppKit на resign-key перекрашивает
        // титлбар системным серым и возвращает непрозрачный фон — переустанавливаем
        // безрамочный конфиг на каждое такое событие, иначе «сначала норм, потом серо».
        var chromeObservers: [NSObjectProtocol] = []
        // Поколение конфигурации: растёт на каждый apply. Отложенные такты
        // (enforceChrome и centerTop) сверяют своё поколение с текущим и молчат,
        // если оно устарело. Без этого Skip сломал бы главное окно: `done`
        // переключается мгновенно, а такты, заказанные ещё мастером, догнали бы уже
        // обычное окно и вернули ему безрамочный вид и размер 720×880.
        var generation = 0
        // Имя автосейва кадра, которое повесил SwiftUI. Мастер его снимает (иначе
        // macOS восстанавливает старый кадр ПОСЛЕ центрирования) — возвращаем при
        // выходе, чтобы главное окно снова помнило позицию.
        var savedAutosaveName: NSWindow.FrameAutosaveName?
        // Наблюдатели за попытками изменить размер (см. installFrameLock). Список
        // отдельный от chromeObservers: снимаются они вместе, но живут по разным
        // причинам, и путать их значит однажды снять не те.
        var frameObservers: [NSObjectProtocol] = []
        // Пределы кадра и поведение в наборах окон ДО мастера: мастер зажимает
        // размер намертво (lockFrameSize), а главное окно обязано получить свои
        // прежние значения обратно — оно тот же самый NSWindow.
        var savedMinSize: NSSize?
        var savedMaxSize: NSSize?
        var savedCollectionBehavior: NSWindow.CollectionBehavior?
        deinit {
            for observer in chromeObservers + frameObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        // окно у view появляется не сразу — ретраим, пока не поймаем реальный
        // NSWindow (иначе позиционирование ни разу не отрабатывает: в makeNSView
        // containerView.window ещё nil, а в updateNSView guard уже false).
        retryApply(view: containerView, coordinator: context.coordinator, tries: 0)
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window, coordinator: context.coordinator) }
    }

    private func retryApply(view: NSView, coordinator: Coordinator, tries: Int) {
        DispatchQueue.main.async {
            if view.window != nil || tries > 20 {
                apply(to: view.window, coordinator: coordinator)
            } else {
                retryApply(view: view, coordinator: coordinator, tries: tries + 1)
            }
        }
    }

    /// Диспетчер: обновляет поколение, ставит общий тёмный хром и разводит на
    /// онбординговую и обычную ветки. Тело каждой ветки — в отдельном методе.
    private func apply(to window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        // Новая конфигурация обесценивает все отложенные такты прежней.
        coordinator.generation &+= 1
        let generation = coordinator.generation
        applyCommonChrome(to: window)
        if isOnboarding {
            configureOnboardingWindow(window, coordinator: coordinator, generation: generation)
        } else {
            restoreNormalWindow(window, coordinator: coordinator)
        }
    }

    /// Общая часть обеих веток: тёмный прозрачный титлбар, полноразмерный контент,
    /// перетаскивание за фон. Восстановление кадра — только вне онбординга.
    private func applyCommonChrome(to window: NSWindow) {
        // тёмный титлбар как в макете (а не светло-серый материал системы)
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        // на онбординге не даём macOS восстанавливать сохранённый кадр —
        // окно всегда стартует top-center; после мастера главное окно снова
        // помнит свою позицию между запусками.
        window.isRestorable = !isOnboarding
    }

    /// Онбординговая ветка `apply`: заголовок, безрамочный хром с догоняющими
    /// тактами, отвязка автосейва и фиксированный кадр 720×880 top-center.
    private func configureOnboardingWindow(
        _ window: NSWindow, coordinator: Coordinator, generation: Int
    ) {
        window.title = "Foundry — Setup"
        installChromeEnforcement(window, coordinator: coordinator, generation: generation)
        detachFrameAutosave(window, coordinator: coordinator)
        resizeAndPosition(window, coordinator: coordinator, generation: generation)
    }

    /// Ставит безрамочный вид сейчас, догоняет его отложенными тактами (подвиды
    /// титлбара достраиваются не за кадр) и подписывается на смены фокуса окна.
    private func installChromeEnforcement(
        _ window: NSWindow, coordinator: Coordinator, generation: Int
    ) {
        // Безрамочный вид держим ПОСТОЯННО (см. enforceChrome): фон окна
        // прозрачный + скруглённый и клиппированный рамочный вид (NSThemeFrame),
        // чтобы срезать системную рамку и её углы. Один вызов не держится:
        // на resign-key AppKit перекрашивает титлбар серым и возвращает
        // непрозрачный фон — потому переустанавливаем на каждую смену фокуса.
        Self.enforceChrome(window)
        // Первый enforceChrome часто отрабатывает ДО того, как SwiftUI/AppKit
        // достроят подвиды титлбара (серый материал, `_NSTitlebarDecorationView`,
        // сам заголовок) — тогда прятать нечего, и «серая плашка с подписью и
        // бордером» остаётся, а смены фокуса, чтобы переустановить, не случается
        // (окно рождается ключевым). Догоняем несколькими отложенными тактами —
        // как с центрированием: к 0.6с подвиды точно на месте и гасятся.
        for delay in [0.05, 0.15, 0.35, 0.6, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard coordinator.generation == generation else { return }
                Self.enforceChrome(window)
            }
        }
        if coordinator.chromeObservers.isEmpty {
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
            ]
            for name in names {
                let observer = NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak window] _ in
                    MainActor.assumeIsolated {
                        guard let window else { return }
                        Self.enforceChrome(window)
                    }
                }
                coordinator.chromeObservers.append(observer)
            }
        }
    }

    /// Снимает frameAutosaveName, повешенный SwiftUI-WindowGroup (сохранив его для
    /// возврата), — иначе macOS восстановит старый кадр уже ПОСЛЕ центрирования.
    private func detachFrameAutosave(_ window: NSWindow, coordinator: Coordinator) {
        // Отвязать автосейв кадра: SwiftUI-WindowGroup вешает frameAutosaveName,
        // и macOS ВОССТАНАВЛИВАЕТ сохранённый кадр ПОСЛЕ нашего setFrame —
        // окно уезжало из центра туда, где стояло в прошлый раз (isRestorable
        // это не отменяет, это другой механизм). Пустое имя отключает автосейв,
        // и центрирование ниже держится.
        // Запоминаем ТОЛЬКО непустое имя: SwiftUI вешает его не в первый такт, и в
        // части запусков первый `apply` видит окно ещё безымянным. Снимок пустышки
        // намертво: возвращать было бы нечего, и главное окно после мастера до
        // перезапуска не помнило бы свой кадр. Пустое имя — не «нет автосейва», а
        // «ещё не поставили»: следующий такт запомнит настоящее.
        let currentName = window.frameAutosaveName
        if !currentName.isEmpty, coordinator.savedAutosaveName == nil {
            coordinator.savedAutosaveName = currentName
        }
        window.setFrameAutosaveName("")
    }

    /// Держит кадр ровно 720×880: при первой настройке центрирует top-center с
    /// догоняющими тактами, дальше лишь возвращает размер, не трогая позицию.
    private func resizeAndPosition(
        _ window: NSWindow, coordinator: Coordinator, generation: Int
    ) {
        // размер — ПОЛНЫЙ кадр 720×880 (титлбар 44 внутри), как .ob-win в
        // макете. Не setContentSize: тот прибавлял 28px нативного бара. И не
        // 920 (прежняя ошибка): при 880 рабочая зона под титлбаром = 836 =
        // refHeight роя, значит KFIT ровно 1.0 — рой попадает в масштаб макета
        // (при 920 канвас 876 давал KFIT 0.954, рой выходил мельче).
        let size = NSSize(width: 720, height: 880)
        Self.lockFrameSize(window, to: size, coordinator: coordinator)
        installFrameLock(window, to: size, coordinator: coordinator)
        if !coordinator.didPositionWindow {
            coordinator.didPositionWindow = true
            Self.centerTop(window, size: size)
            // WindowGroup докладывает свою каскадную позицию асинхронно ПОСЛЕ
            // нашего setFrame — окно уезжало влево-вверх. Пере-центрируем ещё
            // несколько раз с задержкой, пока раскладка не устаканится; после
            // окно в покое и его можно двигать.
            for delay in [0.05, 0.15, 0.35, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard coordinator.generation == generation else { return }
                    Self.centerTop(window, size: size)
                }
            }
        } else if window.frame.size != size {
            // держим полный размер, не трогая позицию
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
        }
    }

    /// Запирает размер кадра — по ширине И по высоте, всеми замками сразу, потому что
    /// каждый путь ресайза спрашивает своё:
    ///   - тяга за кромку и «зум» (двойной клик по титлбару, зелёная кнопка) —
    ///     `.resizable` в стиле окна;
    ///   - полный экран (View → Enter Full Screen, Full Screen Tile) —
    ///     `collectionBehavior`, стиль окна ему безразличен: окно уезжало в 1728×1080;
    ///   - плитка macOS (Window → Move & Resize), Accessibility и сторонние оконные
    ///     менеджеры двигают кадр напрямую и упираются ТОЛЬКО в `minSize`/`maxSize`:
    ///     окно становилось 852×1004.
    /// Мастер сверстан под ровно 720×880 (рабочая зона = refHeight роя, KFIT 1.0) —
    /// любой другой кадр ломает раскладку.
    @MainActor private static func lockFrameSize(
        _ window: NSWindow, to size: NSSize, coordinator: Coordinator
    ) {
        if coordinator.savedMinSize == nil {
            coordinator.savedMinSize = window.minSize
            coordinator.savedMaxSize = window.maxSize
            coordinator.savedCollectionBehavior = window.collectionBehavior
        }
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.minSize = size
        window.maxSize = size
        var behavior = window.collectionBehavior
        behavior.remove(.fullScreenPrimary)
        behavior.remove(.fullScreenAuxiliary)
        behavior.insert(.fullScreenNone)
        window.collectionBehavior = behavior
    }

    /// Переустанавливает замок на каждую попытку ресайза — ровно как `enforceChrome`
    /// на каждую смену фокуса, и по той же причине: одного вызова не хватает. Окно
    /// принадлежит SwiftUI, и тот на своих обновлениях сцены возвращает СВОИ пределы
    /// и `.resizable` обратно — в момент тяги в окне стояли его `min 640×508` и
    /// `max ∞` (пределы главного контента под мастером), и кромка снова тянулась:
    /// 720 превращалось в 870.
    ///
    /// Три события, разные роли:
    ///   - `willStartLiveResize` — ДО того, как AppKit поведёт тягу: по ходу драга он
    ///     сверяется с min/max, и при равных пределах кромка просто не двигается;
    ///   - `didResize` — сеть для путей без живой тяги. Кадр возвращается СЛЕДУЮЩИМ
    ///     тактом, а не прямо в обработчике: `setFrame` внутри `didResize` — это
    ///     рекурсия по тому же уведомлению;
    ///   - `NSApplication.willUpdate` — такт цикла событий, до обработки меню и
    ///     горячих клавиш. Полный экран не даёт ни одного из двух первых событий: он
    ///     спрашивает `collectionBehavior` НАПРЯМУЮ, а тот к моменту вопроса уже
    ///     переставлен SwiftUI обратно в `.fullScreenPrimary` — пункт «Enter Full
    ///     Screen» оживал, и мастер уезжал в отдельное пространство (окно при этом
    ///     оставалось 720×880 — размер-то заперт, но сидело оно уже в чужом
    ///     полноэкранном пространстве). Переустановка на каждом такте закрывает и этот
    ///     путь, и любой другой, спрашивающий пределы без уведомления.
    private func installFrameLock(_ window: NSWindow, to size: NSSize, coordinator: Coordinator) {
        guard coordinator.frameObservers.isEmpty else { return }
        let windowEvents: [Notification.Name] = [
            NSWindow.willStartLiveResizeNotification, NSWindow.didResizeNotification,
        ]
        for name in windowEvents {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak window, weak coordinator] _ in
                MainActor.assumeIsolated {
                    guard let window, let coordinator else { return }
                    guard reassertLock(window, to: size, coordinator: coordinator) else { return }
                    guard window.frame.size != size else { return }
                    DispatchQueue.main.async {
                        window.setFrame(
                            NSRect(origin: window.frame.origin, size: size), display: true
                        )
                    }
                }
            }
            coordinator.frameObservers.append(observer)
        }
        let tick = NotificationCenter.default.addObserver(
            forName: NSApplication.willUpdateNotification, object: nil, queue: .main
        ) { [weak window, weak coordinator] _ in
            MainActor.assumeIsolated {
                guard let window, let coordinator else { return }
                _ = reassertLock(window, to: size, coordinator: coordinator)
            }
        }
        coordinator.frameObservers.append(tick)
    }

    /// Общее тело наблюдателей замка: переустановить замок, если мастер ещё идёт, и
    /// снять его насовсем, если уже кончился. Возвращает, заперто ли окно сейчас, —
    /// звонящему это нужно, чтобы решать, возвращать ли кадр.
    ///
    /// Мастер мог кончиться, а наблюдатель ещё жить (SwiftUI не обязан прислать
    /// обновление вида, на котором держится `restoreNormalWindow`) — тогда снимаем
    /// замок сами и уходим навсегда.
    @MainActor private func reassertLock(
        _ window: NSWindow, to size: NSSize, coordinator: Coordinator
    ) -> Bool {
        guard isOnboardingNow() else {
            restoreFrameFreedom(window, coordinator: coordinator)
            return false
        }
        Self.lockFrameSize(window, to: size, coordinator: coordinator)
        return true
    }

    /// Зеркало `lockFrameSize` и `installFrameLock`: снимает наблюдателей и возвращает
    /// пределы кадра, какими они были до мастера. Идемпотентно — зовётся и из обычной
    /// ветки `apply`, и из самих наблюдателей.
    @MainActor private func restoreFrameFreedom(_ window: NSWindow, coordinator: Coordinator) {
        for observer in coordinator.frameObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        coordinator.frameObservers.removeAll()
        window.styleMask.insert(.resizable)
        window.standardWindowButton(.zoomButton)?.isEnabled = true
        if let minSize = coordinator.savedMinSize, let maxSize = coordinator.savedMaxSize {
            window.minSize = minSize
            window.maxSize = maxSize
            coordinator.savedMinSize = nil
            coordinator.savedMaxSize = nil
        }
        if let behavior = coordinator.savedCollectionBehavior {
            window.collectionBehavior = behavior
            coordinator.savedCollectionBehavior = nil
        }
    }

    /// Обычная ветка `apply`: снять наблюдателей, развернуть весь безрамочный вид
    /// обратно (`restoreChrome`), вернуть автосейв, заголовок и изменяемый размер.
    private func restoreNormalWindow(_ window: NSWindow, coordinator: Coordinator) {
        // обычное окно: снимаем наблюдателей и разворачиваем ВЕСЬ безрамочный
        // вид обратно (см. restoreChrome — зеркало enforceChrome).
        for observer in coordinator.chromeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        coordinator.chromeObservers.removeAll()
        restoreFrameFreedom(window, coordinator: coordinator)
        Self.restoreChrome(window)
        if let saved = coordinator.savedAutosaveName {
            window.setFrameAutosaveName(saved)
            coordinator.savedAutosaveName = nil
        }
        // Изменяемый размер, «зум» и пределы кадра вернул restoreFrameFreedom выше —
        // здесь остаётся только заголовок.
        window.title = "Foundry"
    }

    /// Переустанавливаемый безрамочный вид окна онбординга. Зовётся при первичной
    /// настройке и на каждую смену фокуса — иначе AppKit на resign-key вернёт
    /// системный серый титлбар и непрозрачный фон, а рамка проступит обратно.
    @MainActor private static func enforceChrome(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        // БЕЗ БОРДЕРА: на этой macOS родной 1px-бордер titled-окна снимается только
        // вместе с тенью — они один механизм. Делаем окно прозрачным и выключаем
        // тень: сервер больше не обводит силуэт светлым кантом. Скругление углов —
        // в SwiftUI (.clipShape). Цена — нет родной тени (её при желании рисуем сами).
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // NSThemeFrame не клиппируем (даёт кант-артефакт). Гасим хром титлбара:
        // серый материал и линию-накладку — «светофор» (NSButton) остаётся.
        if let frameView = window.frameView {
            frameView.layer?.cornerRadius = 0
            frameView.layer?.masksToBounds = false
            frameView.layer?.borderWidth = 0
            setTitlebarChromeHidden(true, in: frameView)
        }
    }

    /// Возврат обычного вида — ЗЕРКАЛО `enforceChrome`. Мастер и главное окно это
    /// один и тот же NSWindow (`WindowConfigurator` висит на корне, `isOnboarding`
    /// переключается на ходу), поэтому всё выключенное надо включить обратно: иначе
    /// после Skip или финала главное окно до перезапуска оставалось без тени, без
    /// заголовка и с погашенным хромом титлбара. Правило: любое поле, которое трогает
    /// `enforceChrome`, обязано иметь строку здесь — кроме `appearance` и
    /// `titlebarAppearsTransparent`, они одинаковы для ОБОИХ режимов и ставятся выше,
    /// в общей части `apply`; возвращать тут нечего.
    @MainActor private static func restoreChrome(_ window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = NSColor(srgbRed: 14 / 255, green: 11 / 255, blue: 20 / 255, alpha: 1)
        window.hasShadow = true
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .automatic
        for view in [window.contentView, window.frameView] {
            view?.layer?.cornerRadius = 0
            view?.layer?.masksToBounds = false
        }
        if let frameView = window.frameView {
            setTitlebarChromeHidden(false, in: frameView)
        }
    }

    /// Гасит или возвращает хром титлбара: системный материал (`NSVisualEffectView`,
    /// серый на неактивном окне) и декоративную накладку (`_NSTitlebarDecorationView` —
    /// это линия-разделитель под баром). Кнопки-«светофор» (`NSButton` в
    /// `NSTitlebarView`) не трогаем — остаются видимыми и рабочими. Один обход на оба
    /// направления: так набор классов не разъедется между «спрятать» и «вернуть».
    @MainActor private static func setTitlebarChromeHidden(_ hidden: Bool, in frameView: NSView) {
        func walk(_ view: NSView, underTitlebar: Bool) {
            let className = String(describing: type(of: view))
            let isTitlebar = underTitlebar || className == "NSTitlebarContainerView"
            if isTitlebar, view is NSVisualEffectView || className == "_NSTitlebarDecorationView" {
                view.isHidden = hidden
            }
            for sub in view.subviews { walk(sub, underTitlebar: isTitlebar) }
        }
        walk(frameView, underTitlebar: false)
    }

    /// Ставит окно по центру по горизонтали, прижав к верху рабочей зоны экрана.
    private static func centerTop(_ window: NSWindow, size: NSSize) {
        guard let screen = window.screen ?? NSScreen.main else {
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
            window.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.minX + (visibleFrame.width - size.width) / 2
        let y = visibleFrame.maxY - size.height
        window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }
}
