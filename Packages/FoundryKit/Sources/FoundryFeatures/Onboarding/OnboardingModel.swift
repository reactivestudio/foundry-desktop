import SwiftUI

/// Машина состояний мастера первого запуска: шесть экранов, двухтактные переходы,
/// имитация установки (Install → Installing… → ✓, как в принятом прототипе),
/// финальный разлёт с передачей управления главному окну.
///
/// Установки визуально имитируются — экран верен прототипу пиксель-в-пиксель;
/// реальные инсталляции агентов/расширений сюда не подключены.
@MainActor
@Observable
final class OnboardingModel {
    // экран и его анимация входа/выхода (двухтактный переход)
    var step = 0
    var contentOpacity: Double = 1
    var contentOffset: CGFloat = 0
    /// Идёт ли межэкранный переход. Пока true, контейнер запекает контент в одну
    /// GPU-текстуру (.drawingGroup) — тяжёлые парящие тени блюрятся один раз, а
    /// не каждый кадр; в покое снимается, текст снова векторный и резкий.
    private(set) var animating = false

    // агенты
    let agents: [OBCard]
    var installedAgents: Set<String> = []
    var installingAgent: String?
    var selectedAgent: String?

    // расширения
    let exts: [OBCard]
    var installedExts: Set<String> = []
    var installingExt: String?

    // настройки
    struct Setting: Identifiable {
        let id: String
        let name: String
        let desc: String
        var on: Bool
    }
    var settings: [Setting] = [
        .init(id: "notch", name: "Notch mode", desc: "Stage progress around the notch", on: true),
        .init(id: "notif", name: "Notifications", desc: "When a stage finishes or fails", on: true),
        .init(id: "keychain", name: "Keychain", desc: "Tokens live there, not in files", on: true),
        .init(id: "login", name: "Launch at login", desc: "Resumes stages after restart", on: false),
        .init(id: "review", name: "Merge review", desc: "Nothing merges until you approve", on: true),
    ]

    // разрешения macOS
    struct Permission: Identifiable {
        let id: String
        let name: String
        let desc: String
        var granted: Bool
    }
    var permissions: [Permission] = [
        .init(
            id: "notif", name: "Notifications", desc: "A stage finished or needs your review", granted: false),
        .init(id: "a11y", name: "Accessibility", desc: "Global ⌥ Space and the notch panel", granted: false),
    ]

    // разлёт
    var bursting = false
    var revealed = false
    private var didReveal = false
    private var didFinish = false

    /// Позвать раскрытие главного окна (разлёт перевалил за половину).
    var onReveal: () -> Void = {}
    /// Разлёт завершён — мастер можно снять.
    var onFinished: () -> Void = {}

    let stepCount = 6

    // MARK: - Раскладка экрана (единый нижний зазор до пагинации)

    /// Единый нижний воздух экрана над пагинацией — эталон взят с приветствия (s6=32).
    /// ОДИН на все шесть экранов: этим и «фиксируется» композиция — нижний элемент
    /// любого экрана (кнопка / ряд карточек / панель) встаёт на равном расстоянии до
    /// точек. Прежде рабочие экраны висели у верха, а Agent имел зазор 0 — расстояние
    /// до пагинации скакало от экрана к экрану.
    let screenPadBottom: CGFloat = 32

    init() {
        func tint(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(red: r / 255, green: g / 255, blue: b / 255).opacity(0.14)
        }
        agents = [
            OBCard(
                id: "claude", glyph: .claude, bare: false, tint: tint(217, 119, 87),
                vendor: "Anthropic", name: "Claude Code",
                newFact: "Pro / Max plan or API key", secondFact: "Max plan · Opus 4.8",
                signed: "v2.1.4 · signed in", showsInstall: true),
            OBCard(
                id: "codex", glyph: .openai, bare: false, tint: nil,
                vendor: "OpenAI", name: "Codex CLI",
                newFact: "ChatGPT plan or API key", secondFact: "ChatGPT Pro · GPT-5.2",
                signed: "v0.9.2 · signed in", showsInstall: true),
            OBCard(
                id: "gemini", glyph: .gemini, bare: false, tint: tint(66, 133, 244),
                vendor: "Google", name: "Gemini CLI",
                newFact: "Google account · free tier", secondFact: "Google account · free tier",
                signed: "v0.8.0 · signed in", showsInstall: true),
        ]
        exts = [
            OBCard(
                id: "plugin", glyph: .plugin, bare: true, tint: nil,
                vendor: "Foundry", name: "Claude Plugin",
                newFact: "7 skills · 4 agents", secondFact: nil,
                signed: "in ~/.claude", showsInstall: true),
            OBCard(
                id: "cli", glyph: .cli, bare: true, tint: nil,
                vendor: "Foundry", name: "CLI",
                newFact: "stage runner · worktrees", secondFact: nil,
                signed: "/usr/local/bin/foundry", showsInstall: true),
        ]
    }

    // MARK: - Переходы (двухтактные: уход 300ms → свап → вход 640ms; плавно, без рывка)

    // Куда переход держит курс. Быстрые нажатия НЕ плодят отдельные анимации и не
    // снимаются рывком «в лоб» — они лишь двигают эту цель; текущий такт на своём
    // стыке доедет сразу до самого свежего адреса. Так три быстрых стрелки = один
    // плавный переход к финальному экрану, без мельтешения гашений.
    private var pendingTarget: Int?

    func go(to next: Int) {
        guard next != step, !bursting else { return }
        pendingTarget = next
        if !animating { startTransition() }
    }

    /// Один такт перехода: увести текущий экран (гашение + лёгкий подъём) → на
    /// стыке свапнуть на САМУЮ свежую цель (сжатые быстрые нажатия) → ввести новый.
    /// Хвостом проверяем, не накопились ли ещё нажатия за время ввода — тогда
    /// плавно продолжаем следующим тактом (без стыка кадров и рывка).
    private func startTransition() {
        guard let target = pendingTarget, target != step else {
            pendingTarget = nil
            animating = false
            return
        }
        animating = true
        // Уход: плавная кривая (разгон И затухание, control2 не в углу) — контент не
        // обрывается на полной скорости, а мягко тает, поднимаясь. Дольше прежнего.
        withAnimation(.timingCurve(0.35, 0, 0.35, 1, duration: 0.30)) {
            contentOpacity = 0
            contentOffset = -12
        } completion: { [self] in
            let dest = pendingTarget ?? target
            pendingTarget = nil
            step = dest
            contentOffset = 14
            // Вход: длинный дом-decel (0.2,0,0,1) — новый экран мягко доезжает снизу
            // и проявляется, без рывка на старте.
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.64)) {
                contentOpacity = 1
                contentOffset = 0
            } completion: { [self] in
                if let p = pendingTarget, p != step {
                    startTransition()  // за время ввода докрутили ещё — продолжаем гладко
                } else {
                    pendingTarget = nil
                    animating = false
                }
            }
        }
    }

    /// Навигация стрелками (как клик по точкам пагинации): вправо — дальше,
    /// влево — назад, в пределах [0, stepCount-1].
    ///
    /// Считаем от УЖЕ намеченной цели (`pendingTarget`), а не от `step` — тот в
    /// разгар перехода ещё не сдвинулся, и два быстрых нажатия иначе целили бы в
    /// один и тот же экран (+1, +1). Теперь второе нажатие честно даёт +2.
    func goNext() {
        let base = pendingTarget ?? step
        if base < stepCount - 1 { go(to: base + 1) }
    }
    func goPrev() {
        let base = pendingTarget ?? step
        if base > 0 { go(to: base - 1) }
    }

    // MARK: - Карточки

    func tapAgent(_ id: String) {
        if installedAgents.contains(id) {
            selectedAgent = id
            go(to: 2)
            return
        }
        guard installingAgent == nil else { return }
        installingAgent = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [self] in
            installingAgent = nil
            installedAgents.insert(id)
            selectedAgent = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { self.go(to: 2) }
        }
    }

    func tapExt(_ id: String) {
        if installedExts.contains(id) {
            if installedExts.count == exts.count { go(to: 3) }
            return
        }
        guard installingExt == nil else { return }
        installingExt = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [self] in
            installingExt = nil
            installedExts.insert(id)
            if installedExts.count == exts.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { self.go(to: 3) }
            }
        }
    }

    func toggle(_ id: String) {
        guard let i = settings.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(OB.easeReal(0.30)) { settings[i].on.toggle() }
    }

    func grant(_ id: String) {
        guard let i = permissions.firstIndex(where: { $0.id == id }) else { return }
        permissions[i].granted = true
        if permissions.allSatisfy(\.granted) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { self.go(to: 5) }
        }
    }

    // MARK: - Финал

    func finish() {
        guard !bursting else { return }
        bursting = true
        withAnimation(OB.easeReal(0.15)) { contentOpacity = 0 }  // stage гаснет
    }

    /// Прогресс разлёта от OnboardingSwarmView.
    func burstProgress(_ p: Double) {
        if p >= 0.55 && !didReveal {
            didReveal = true
            onReveal()
        }
        if p >= 0.999 && !didFinish {
            didFinish = true
            onFinished()
        }
    }
}
