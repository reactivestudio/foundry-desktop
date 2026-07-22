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
    struct Setting: Identifiable { let id: String; let name: String; let desc: String; var on: Bool }
    var settings: [Setting] = [
        .init(id: "notch", name: "Notch mode", desc: "Stage progress around the notch", on: true),
        .init(id: "notif", name: "Notifications", desc: "When a stage finishes or fails", on: true),
        .init(id: "keychain", name: "Keychain", desc: "Tokens live there, not in files", on: true),
        .init(id: "login", name: "Launch at login", desc: "Resumes stages after restart", on: false),
        .init(id: "review", name: "Merge review", desc: "Nothing merges until you approve", on: true),
    ]

    // разрешения macOS
    struct Permission: Identifiable { let id: String; let name: String; let desc: String; var granted: Bool }
    var permissions: [Permission] = [
        .init(id: "notif", name: "Notifications", desc: "A stage finished or needs your review", granted: false),
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

    // MARK: - Раскладка экрана (как в макете: hero-full / veil-low / standard)

    /// Состояние завесы поверх роя (`.ob-veil`): none — рой целиком (приветствие,
    /// Готово); low — затемнение утащено под карточки (Agent); standard — рабочие
    /// экраны на чистом фоне. Кросс-фейд между состояниями рисует контейнер.
    enum VeilState { case none, standard, low }
    var veilState: VeilState {
        if step == 0 || step == stepCount - 1 { return .none }   // hero-full
        if step == 1 { return .low }                             // veil-low (Agent)
        return .standard
    }

    /// Полный орб без завесы — только там, где экран почти пуст (приветствие, Готово).
    var isHeroFull: Bool { step == 0 || step == stepCount - 1 }

    /// Контент прижат к низу (`justify-content: flex-end`) на приветствии, Agent и
    /// Готово; на рабочих экранах (Extensions/Settings/Permissions) — к верху.
    var bottomPinned: Bool { step == 0 || step == 1 || step == stepCount - 1 }

    /// Доп. нижний отступ экрана (`.ob-screen padding-bottom`): приветствие и
    /// Готово — s6 = 32 (воздух над пагинацией); Agent — 0.
    var screenPadBottom: CGFloat { (step == 0 || step == stepCount - 1) ? 32 : 0 }

    init() {
        func tint(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(red: r / 255, green: g / 255, blue: b / 255).opacity(0.14)
        }
        agents = [
            OBCard(id: "claude", glyph: .claude, bare: false, tint: tint(217, 119, 87),
                   vendor: "Anthropic", name: "Claude Code",
                   newFact: "Pro / Max plan or API key", secondFact: "Max plan · Opus 4.8",
                   signed: "v2.1.4 · signed in", showsInstall: true),
            OBCard(id: "codex", glyph: .openai, bare: false, tint: nil,
                   vendor: "OpenAI", name: "Codex CLI",
                   newFact: "ChatGPT plan or API key", secondFact: "ChatGPT Pro · GPT-5.2",
                   signed: "v0.9.2 · signed in", showsInstall: true),
            OBCard(id: "gemini", glyph: .gemini, bare: false, tint: tint(66, 133, 244),
                   vendor: "Google", name: "Gemini CLI",
                   newFact: "Google account · free tier", secondFact: "Google account · free tier",
                   signed: "v0.8.0 · signed in", showsInstall: true),
        ]
        exts = [
            OBCard(id: "plugin", glyph: .plugin, bare: true, tint: nil,
                   vendor: "Foundry", name: "Claude Plugin",
                   newFact: "7 skills · 4 agents", secondFact: nil,
                   signed: "in ~/.claude", showsInstall: true),
            OBCard(id: "cli", glyph: .cli, bare: true, tint: nil,
                   vendor: "Foundry", name: "CLI",
                   newFact: "stage runner · worktrees", secondFact: nil,
                   signed: "/usr/local/bin/foundry", showsInstall: true),
        ]
    }

    // MARK: - Переходы (двухтактные: уход 320ms, свап на 300ms, вход 560/680ms)

    func go(to next: Int) {
        guard next != step, !animating, !bursting else { return }
        animating = true
        withAnimation(.timingCurve(0.33, 0, 0.67, 1, duration: 0.32)) { contentOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [self] in
            step = next
            contentOffset = 22
            withAnimation(.timingCurve(0.33, 0, 0.67, 1, duration: 0.56)) { contentOpacity = 1 }
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.68)) { contentOffset = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) { self.animating = false }
        }
    }

    /// Навигация стрелками (как клик по точкам пагинации): вправо — дальше,
    /// влево — назад, в пределах [0, stepCount-1].
    func goNext() { if step < stepCount - 1 { go(to: step + 1) } }
    func goPrev() { if step > 0 { go(to: step - 1) } }

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
        withAnimation(OB.easeReal(0.15)) { contentOpacity = 0 }   // stage гаснет
    }

    /// Прогресс разлёта от OnboardingSwarmView.
    func burstProgress(_ p: Double) {
        if p >= 0.55 && !didReveal { didReveal = true; onReveal() }
        if p >= 0.999 && !didFinish { didFinish = true; onFinished() }
    }
}
