import Foundation
import FoundryCore
import Subprocess

#if canImport(System)
    import System
#endif

public enum ClaudeRunError: Error, LocalizedError {
    case claudeNotFound
    case badExit(code: String, stderrTail: String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Бинарь claude не найден. Установи Claude Code или задай CLAUDE_PATH."
        case .badExit(let code, let stderrTail):
            let tail = stderrTail.isEmpty ? "" : "\n\(stderrTail)"
            return "claude завершился с ошибкой (\(code)).\(tail)"
        }
    }
}

/// Запуск `claude -p` в каталоге проекта со стримом доменных событий.
/// Практики 06 §2: swift-subprocess, teardown SIGINT → graceful,
/// конкурентный дренаж stderr, разбор полными NDJSON-строками.
public struct ClaudeRunner: Sendable {

    public init() {}

    /// GUI-приложение не наследует PATH шелла — путь к claude резолвим сами.
    public static func locateClaude() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let override = ProcessInfo.processInfo.environment["CLAUDE_PATH"] {
            candidates.insert(override, at: 0)
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    public func stream(
        prompt: String,
        projectDirectory: String,
        permissionMode: PermissionMode
    ) -> AsyncThrowingStream<ClaudeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let claudePath = Self.locateClaude() else {
                    continuation.finish(throwing: ClaudeRunError.claudeNotFound)
                    return
                }

                var arguments = [
                    "-p", prompt,
                    "--output-format", "stream-json",
                    "--verbose",
                    "--include-partial-messages",
                ]
                if permissionMode != .default {
                    arguments += ["--permission-mode", permissionMode.rawValue]
                }

                var options = PlatformOptions()
                // Своя сессия: teardown-сигналы уходят всей группе процессов
                // claude, не задевая родителя.
                options.createSession = true
                options.teardownSequence = [
                    .send(
                        signal: .interrupt,
                        toProcessGroup: true,
                        allowedDurationToNextStep: .seconds(3)
                    ),
                    .gracefulShutDown(
                        toProcessGroup: true,
                        allowedDurationToNextStep: .seconds(5)
                    ),
                ]

                // claude спавнит свои тулзы (Bash, git) — PATH дополняем сами.
                let binDir = (claudePath as NSString).deletingLastPathComponent
                let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
                let path = "\(binDir):/opt/homebrew/bin:/usr/local/bin:\(inheritedPath)"

                do {
                    let result = try await run(
                        .path(FilePath(claudePath)),
                        arguments: Arguments(arguments),
                        environment: .inherit.updating(["PATH": path]),
                        workingDirectory: FilePath(projectDirectory),
                        platformOptions: options,
                        input: .none,
                        output: .sequence,
                        error: .sequence
                    ) { execution in
                        // stderr дренируется конкурентно — иначе pipe-deadlock.
                        async let stderrTail = Self.collectTail(execution.standardError)
                        // Одна stream-json строка бывает мегабайты (полный
                        // result) — дефолтных 128 КБ на строку мало.
                        let lines = execution.standardOutput.strings(
                            separatedBy: .lineBreaks,
                            bufferingPolicy: .maxLineLength(32 * 1024 * 1024)
                        )
                        for try await line in lines {
                            guard !line.isEmpty else { continue }
                            for event in ClaudeEventDecoder.decode(line) {
                                continuation.yield(event)
                            }
                        }
                        return await stderrTail
                    }
                    guard result.terminationStatus.isSuccess else {
                        throw ClaudeRunError.badExit(
                            code: "\(result.terminationStatus)",
                            stderrTail: result.closureOutput
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // UI перестал слушать (Stop, закрытие окна) → SIGINT ребёнку.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func collectTail(
        _ stderr: SubprocessOutputSequence
    ) async -> String {
        var tail = ""
        do {
            for try await line in stderr.strings() {
                tail += line + "\n"
                if tail.count > 4000 { tail = String(tail.suffix(4000)) }
            }
        } catch {
            // stderr — только диагностика; ошибки чтения не важны
        }
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
