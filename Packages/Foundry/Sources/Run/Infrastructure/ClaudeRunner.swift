import Foundation
import Subprocess
import SwiftContext

#if canImport(System)
    import System
#endif

public enum ClaudeRunError: Error, LocalizedError {
    case claudeNotFound
    case launchFailed(reason: String)
    case badExit(code: String, stderrTail: String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Бинарь claude не найден. Установи Claude Code или задай CLAUDE_PATH."
        case .launchFailed(let reason):
            return "Не удалось запустить claude: \(reason)"
        case .badExit(let code, let stderrTail):
            let tail = stderrTail.isEmpty ? "" : "\n\(stderrTail)"
            return "claude завершился с ошибкой (\(code)).\(tail)"
        }
    }
}

/// Запуск `claude -p` в каталоге проекта со стримом доменных событий.
/// Практики 06, пункт 2: swift-subprocess, teardown SIGINT → graceful,
/// конкурентный дренаж stderr, разбор полными NDJSON-строками.
/// `@Component` — скан построит цепочку наследования сам (`ClaudeRunner: AgentRunner`) и соберёт
/// адаптер в контейнер по ней (аналог `@Component` Spring), ручная ассембли не нужна.
@Component
public struct ClaudeRunner: AgentRunner {

    private enum Limit {
        /// Одна stream-json строка бывает мегабайты (полный result) — дефолтных
        /// 128 КБ на строку мало, поднимаем потолок до 32 МБ.
        static let maxLineBytes = 32 * 1024 * 1024
        /// Сколько хвоста stderr держим для диагностики `badExit` (символы).
        static let stderrTailChars = 4000
    }

    public init() {}

    /// GUI-приложение не наследует PATH шелла — путь к claude резолвим сами.
    public static func locateClaude() -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let overridePath = ProcessInfo.processInfo.environment["CLAUDE_PATH"] {
            candidates.insert(overridePath, at: 0)
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// Аргументы `claude -p` под заданный промпт и режим разрешений. `--permission-mode`
    /// добавляется только для не-`default` режима (дефолт claude подразумевает сам).
    private static func makeArguments(prompt: String, permissionMode: PermissionMode) -> [String] {
        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
        ]
        if permissionMode != .default {
            arguments += ["--permission-mode", permissionMode.rawValue]
        }
        return arguments
    }

    /// PlatformOptions с teardown-каскадом SIGINT → graceful на всю группу процессов.
    private static func makePlatformOptions() -> PlatformOptions {
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
        return options
    }

    /// PATH для ребёнка: каталог самого claude + Homebrew/local + унаследованный PATH —
    /// claude спавнит свои тулзы (Bash, git), а GUI-процесс шелловский PATH не наследует.
    private static func childEnvironmentPath(claudePath: String) -> String {
        let binDir = (claudePath as NSString).deletingLastPathComponent
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return "\(binDir):/opt/homebrew/bin:/usr/local/bin:\(inheritedPath)"
    }

    public func stream(
        prompt: String,
        projectDirectory: String,
        permissionMode: PermissionMode
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let claudePath = Self.locateClaude() else {
                    continuation.finish(throwing: ClaudeRunError.claudeNotFound)
                    return
                }

                let arguments = Self.makeArguments(prompt: prompt, permissionMode: permissionMode)
                let options = Self.makePlatformOptions()
                let environmentPath = Self.childEnvironmentPath(claudePath: claudePath)

                do {
                    let result = try await run(
                        .path(FilePath(claudePath)),
                        arguments: Arguments(arguments),
                        environment: .inherit.updating(["PATH": environmentPath]),
                        workingDirectory: FilePath(projectDirectory),
                        platformOptions: options,
                        input: .none,
                        output: .sequence,
                        error: .sequence
                    ) { execution in
                        // stderr дренируется конкурентно — иначе pipe-deadlock.
                        async let stderrTail = Self.collectTail(execution.standardError)
                        let lines = execution.standardOutput.strings(
                            separatedBy: .lineBreaks,
                            bufferingPolicy: .maxLineLength(Limit.maxLineBytes)
                        )
                        for try await line in lines {
                            guard !line.isEmpty else { continue }
                            for event in ClaudeEventDecoder.decode(line: line) {
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
                } catch is CancellationError {
                    // Отмена (Stop / закрытие окна) — не сбой запуска: пробрасываем
                    // как есть, стор переводит ран в «Остановлено».
                    continuation.finish(throwing: CancellationError())
                } catch let error as ClaudeRunError {
                    // Наши доменные (`badExit`) уже говорят на языке домена.
                    continuation.finish(throwing: error)
                } catch {
                    // Чужая ошибка инфраструктуры (Subprocess/System при спавне) не
                    // течёт наружу сырой — заворачиваем в доменную `launchFailed`.
                    continuation.finish(
                        throwing: ClaudeRunError.launchFailed(reason: error.localizedDescription))
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
                if tail.count > Limit.stderrTailChars {
                    tail = String(tail.suffix(Limit.stderrTailChars))
                }
            }
        } catch {
            // stderr — только диагностика, на исход рана не влияет. Но глушить
            // ошибку чтения молча нельзя: то, что успели собрать, вернём, а сам
            // обрыв запишем в системный лог.
            CLILog.runner.debug("чтение stderr прервано: \(error.localizedDescription, privacy: .public)")
        }
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
