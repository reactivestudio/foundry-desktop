import FoundryCore
import Testing

@testable import FoundryCLI

@Suite("ClaudeEventDecoder")
struct ClaudeEventDecoderTests {

    @Test("system init → sessionStarted")
    func systemInit() {
        let line =
            #"{"type":"system","subtype":"init","session_id":"abc-123","model":"claude-fable-5","cwd":"/tmp/demo","tools":["Bash"]}"#
        #expect(
            ClaudeEventDecoder.decode(line) == [
                .sessionStarted(SessionInit(sessionID: "abc-123", model: "claude-fable-5", cwd: "/tmp/demo"))
            ])
    }

    @Test("thinking-дельта из stream_event")
    func thinkingDelta() {
        let line =
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"хм"}}}"#
        #expect(ClaudeEventDecoder.decode(line) == [.thinkingDelta("хм")])
    }

    @Test("text-дельта из stream_event")
    func textDelta() {
        let line =
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Привет"}}}"#
        #expect(ClaudeEventDecoder.decode(line) == [.textDelta("Привет")])
    }

    @Test("content_block_start открывает блок; tool_use-блок не открывает")
    func blockStart() {
        let thinking =
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}}"#
        #expect(ClaudeEventDecoder.decode(thinking) == [.blockStarted(.thinking)])

        let tool =
            #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t1","name":"Bash","input":{}}}}"#
        #expect(ClaudeEventDecoder.decode(tool).isEmpty)
    }

    @Test("assistant-сообщение: только tool_use, текст не дублируется")
    func assistantToolUse() {
        let line =
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"смотрю"},{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/tmp/a.txt"}}]}}"#
        #expect(
            ClaudeEventDecoder.decode(line) == [
                .toolUse(name: "Read", inputSummary: "file_path: /tmp/a.txt")
            ])
    }

    @Test("tool_result строкой и массивом блоков")
    func toolResult() {
        let plain =
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#
        #expect(ClaudeEventDecoder.decode(plain) == [.toolResult(summary: "ok", isError: false)])

        let blocks =
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":[{"type":"text","text":"нет файла"}]}]}}"#
        #expect(ClaudeEventDecoder.decode(blocks) == [.toolResult(summary: "нет файла", isError: true)])
    }

    @Test("result → finished")
    func result() {
        let line =
            #"{"type":"result","subtype":"success","is_error":false,"result":"Готово","duration_ms":5120,"num_turns":3,"total_cost_usd":0.0421,"session_id":"abc-123"}"#
        #expect(
            ClaudeEventDecoder.decode(line) == [
                .finished(
                    RunResult(
                        text: "Готово",
                        isError: false,
                        durationMS: 5120,
                        costUSD: 0.0421,
                        turns: 3,
                        sessionID: "abc-123"
                    ))
            ])
    }

    @Test("неизвестный тип и мусор не роняют ран")
    func tolerance() {
        #expect(
            ClaudeEventDecoder.decode(#"{"type":"telemetry_v9","x":1}"#) == [.unknown(type: "telemetry_v9")])
        #expect(ClaudeEventDecoder.decode("не json") == [.unknown(type: "unparsable")])
        // Служебные события стрима молча пропускаются
        #expect(
            ClaudeEventDecoder.decode(#"{"type":"stream_event","event":{"type":"message_start"}}"#).isEmpty)
    }
}
