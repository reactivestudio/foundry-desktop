import Foundation
import FoundryCore

/// Маппинг NDJSON-строк `claude -p --output-format stream-json` в доменные
/// события. Толерантный: неизвестный/битый тип — `.unknown`, не ошибка
/// (practices 06 §2.4: обновление claude не должно ронять приложение).
public enum ClaudeEventDecoder {

    /// Одна строка может дать несколько доменных событий
    /// (assistant-сообщение с пачкой tool_use-блоков).
    public static func decode(_ line: String) -> [ClaudeEvent] {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any],
            let type = root["type"] as? String
        else {
            return [.unknown(type: "unparsable")]
        }

        switch type {
        case "system":
            return decodeSystem(root)
        case "stream_event":
            return decodeStreamEvent(root)
        case "assistant":
            return decodeAssistant(root)
        case "user":
            return decodeUser(root)
        case "result":
            return decodeResult(root)
        default:
            return [.unknown(type: type)]
        }
    }

    // MARK: - system

    private static func decodeSystem(_ root: [String: Any]) -> [ClaudeEvent] {
        guard root["subtype"] as? String == "init" else { return [] }
        return [.sessionStarted(SessionInit(
            sessionID: root["session_id"] as? String ?? "?",
            model: root["model"] as? String ?? "?",
            cwd: root["cwd"] as? String ?? "?"
        ))]
    }

    // MARK: - stream_event (токен-дельты, --include-partial-messages)

    private static func decodeStreamEvent(_ root: [String: Any]) -> [ClaudeEvent] {
        guard
            let event = root["event"] as? [String: Any],
            let eventType = event["type"] as? String
        else { return [] }

        switch eventType {
        case "content_block_start":
            guard
                let block = event["content_block"] as? [String: Any],
                let blockType = block["type"] as? String
            else { return [] }
            switch blockType {
            case "thinking": return [.blockStarted(.thinking)]
            case "text": return [.blockStarted(.text)]
            default: return [] // tool_use придёт целиком в assistant-сообщении
            }

        case "content_block_delta":
            guard
                let delta = event["delta"] as? [String: Any],
                let deltaType = delta["type"] as? String
            else { return [] }
            switch deltaType {
            case "thinking_delta":
                return (delta["thinking"] as? String).map { [.thinkingDelta($0)] } ?? []
            case "text_delta":
                return (delta["text"] as? String).map { [.textDelta($0)] } ?? []
            default:
                return [] // input_json_delta и пр. — вход тула показываем целиком
            }

        default:
            return [] // message_start/stop, ping — служебные
        }
    }

    // MARK: - assistant (полные сообщения; текст/thinking уже пришли дельтами)

    private static func decodeAssistant(_ root: [String: Any]) -> [ClaudeEvent] {
        contentBlocks(root).compactMap { block in
            guard block["type"] as? String == "tool_use" else { return nil }
            let name = block["name"] as? String ?? "?"
            let input = (block["input"] as? [String: Any]).map(summarize) ?? ""
            return .toolUse(name: name, inputSummary: input)
        }
    }

    // MARK: - user (tool results)

    private static func decodeUser(_ root: [String: Any]) -> [ClaudeEvent] {
        contentBlocks(root).compactMap { block in
            guard block["type"] as? String == "tool_result" else { return nil }
            let isError = block["is_error"] as? Bool ?? false
            return .toolResult(
                summary: toolResultText(block["content"]),
                isError: isError
            )
        }
    }

    // MARK: - result

    private static func decodeResult(_ root: [String: Any]) -> [ClaudeEvent] {
        let isError = root["is_error"] as? Bool ?? (root["subtype"] as? String != "success")
        return [.finished(RunResult(
            text: root["result"] as? String ?? "",
            isError: isError,
            durationMS: root["duration_ms"] as? Int ?? 0,
            costUSD: root["total_cost_usd"] as? Double,
            turns: root["num_turns"] as? Int ?? 0,
            sessionID: root["session_id"] as? String ?? "?"
        ))]
    }

    // MARK: - helpers

    private static func contentBlocks(_ root: [String: Any]) -> [[String: Any]] {
        guard
            let message = root["message"] as? [String: Any],
            let content = message["content"] as? [[String: Any]]
        else { return [] }
        return content
    }

    /// Вход тула — компактная однострочная выжимка `ключ: значение`.
    private static func summarize(_ input: [String: Any]) -> String {
        input
            .sorted { $0.key < $1.key }
            .map { key, value in "\(key): \(scalarDescription(value))" }
            .joined(separator: " · ")
            .clipped(to: 300)
    }

    private static func scalarDescription(_ value: Any) -> String {
        switch value {
        case let string as String: return string.clipped(to: 120)
        case let number as NSNumber: return number.stringValue
        default: return "…"
        }
    }

    /// Контент tool_result бывает строкой или массивом блоков.
    private static func toolResultText(_ content: Any?) -> String {
        switch content {
        case let string as String:
            return string.clipped(to: 300)
        case let blocks as [[String: Any]]:
            return blocks
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .clipped(to: 300)
        default:
            return ""
        }
    }
}

extension String {
    func clipped(to limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "…"
    }
}
