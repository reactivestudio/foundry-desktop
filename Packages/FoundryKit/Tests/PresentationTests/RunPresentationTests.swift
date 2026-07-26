import Testing

@testable import Presentation

// Оформление ленты и орба вынесено из вью в презентеры — значит его можно
// прибить тестом. Раньше эти маппинги жили в шести computed-переменных внутри
// SwiftUI-вью и не проверялись ничем.
@Suite("Презентеры run-консоли")
struct RunPresentationTests {

    // ── Лента ──────────────────────────────────────────────────────────────
    @Test("Заголовок и иконка карточки — по виду события")
    func feedTitlesAndIcons() {
        #expect(FeedItemStyle(kind: .info).title == "Система")
        #expect(FeedItemStyle(kind: .info).icon == "info.circle")
        #expect(FeedItemStyle(kind: .thinking).title == "Мышление")
        #expect(FeedItemStyle(kind: .thinking).icon == "brain")
        #expect(FeedItemStyle(kind: .text).title == "Ответ")
        #expect(FeedItemStyle(kind: .text).icon == "text.bubble")
        #expect(FeedItemStyle(kind: .tool(name: "Bash")).title == "Bash")
        #expect(FeedItemStyle(kind: .tool(name: "Bash")).icon == "wrench.and.screwdriver")
    }

    @Test("Тело мышления приглушено, остальные ярче")
    func feedBodyColors() {
        #expect(FeedItemStyle(kind: .thinking).bodyColor == RunPalette.bodyThinking)
        #expect(FeedItemStyle(kind: .info).bodyColor == RunPalette.bodyDefault)
        #expect(FeedItemStyle(kind: .text).bodyColor == RunPalette.bodyDefault)
        #expect(FeedItemStyle(kind: .tool(name: "x")).bodyColor == RunPalette.bodyDefault)
    }

    @Test("Фон карточки: у мышления и тула — свои, у прочих — общий")
    func feedCardBackground() {
        #expect(FeedItemStyle(kind: .thinking).cardBackground == RunPalette.cardThinking)
        #expect(FeedItemStyle(kind: .tool(name: "x")).cardBackground == RunPalette.cardTool)
        #expect(FeedItemStyle(kind: .info).cardBackground == RunPalette.cardDefault)
        #expect(FeedItemStyle(kind: .text).cardBackground == RunPalette.cardDefault)
    }

    // ── Карточка результата ──────────────────────────────────────────────────
    @Test("Стиль карточки результата — по исходу рана")
    func resultCardStyles() {
        let ok = ResultCardStyle(isError: false)
        #expect(ok.title == "Готово")
        #expect(ok.icon == "checkmark.seal.fill")
        #expect(ok.background == [RunPalette.cardDone, RunPalette.cardDoneDeep])

        let fail = ResultCardStyle(isError: true)
        #expect(fail.title == "Завершено с ошибкой")
        #expect(fail.icon == "xmark.octagon.fill")
        #expect(fail.background == [RunPalette.cardFailure, RunPalette.cardFailureDeep])
    }

    // ── Орб ────────────────────────────────────────────────────────────────
    @Test("Палитра и подпись орба — по фазе рана")
    func orbPhaseStyles() {
        #expect(OrbPhaseStyle(phase: .idle).colors == RunPalette.orbIdle)
        #expect(OrbPhaseStyle(phase: .idle).accessibilityLabel == "Готов")
        #expect(OrbPhaseStyle(phase: .running).colors == RunPalette.orbRunning)
        #expect(OrbPhaseStyle(phase: .running).accessibilityLabel == "Claude работает")
        #expect(OrbPhaseStyle(phase: .finished).colors == RunPalette.orbFinished)
        #expect(OrbPhaseStyle(phase: .finished).accessibilityLabel == "Завершено")
        #expect(OrbPhaseStyle(phase: .failed("boom")).colors == RunPalette.orbFailed)
        #expect(OrbPhaseStyle(phase: .failed("boom")).accessibilityLabel == "Ошибка")
    }

    // ── Формат метрик ──────────────────────────────────────────────────────
    @Test("Длительность: до минуты — секунды, дальше — минуты")
    func durationFormat() {
        #expect(RunFormat.duration(milliseconds: 0) == "0.0 с")
        #expect(RunFormat.duration(milliseconds: 1500) == "1.5 с")
        #expect(RunFormat.duration(milliseconds: 59_900) == "59.9 с")
        // Граница ровно на 60 с — уже минуты.
        #expect(RunFormat.duration(milliseconds: 60_000) == "1 мин 00 с")
        #expect(RunFormat.duration(milliseconds: 125_000) == "2 мин 05 с")
    }

    @Test("Стоимость — четыре знака после точки")
    func costFormat() {
        #expect(RunFormat.cost(usd: 0) == "$0.0000")
        #expect(RunFormat.cost(usd: 0.01234) == "$0.0123")
    }

    @Test("Ходы — родительный падеж без склонения по числу")
    func turnsFormat() {
        #expect(RunFormat.turns(0) == "0 ходов")
        #expect(RunFormat.turns(1) == "1 ходов")
        #expect(RunFormat.turns(12) == "12 ходов")
    }

    // ── Строки рана ────────────────────────────────────────────────────────
    @Test("Строки ленты собираются из полей события")
    func runStrings() {
        #expect(RunStrings.sessionStarted(id: "abc", model: "opus") == "Сессия abc · opus")
        #expect(RunStrings.unknownEvent(type: "ping") == "Неизвестное событие: ping")
        #expect(RunStrings.emptyToolResult == "✓")
        #expect(RunStrings.agentReturnedError == "claude вернул ошибку")
        #expect(RunStrings.streamEndedWithoutResult == "Ран завершился без result-события")
        #expect(RunStrings.stopped == "Остановлено")
        #expect(RunStrings.resumeCommand(sessionID: "abc") == "claude --resume abc")
    }
}
