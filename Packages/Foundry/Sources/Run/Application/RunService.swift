import SparkIoC

/// Валидированный ввод сценария запуска рана. Собирается на границе (тонким
/// стором) из состояния экрана; сам сценарий считает поля уже пригодными.
public struct RunCommand: Sendable {
    public let prompt: String
    public let projectDirectory: String
    public let permissionMode: PermissionMode
    /// Импортировать сессию во внешний просмотрщик при старте (политика автоимпорта).
    public let opensSessionInViewer: Bool

    public init(
        prompt: String,
        projectDirectory: String,
        permissionMode: PermissionMode,
        opensSessionInViewer: Bool
    ) {
        self.prompt = prompt
        self.projectDirectory = projectDirectory
        self.permissionMode = permissionMode
        self.opensSessionInViewer = opensSessionInViewer
    }
}

/// Сток прогресса рана. Сценарий толкает сюда события потока и терминальные
/// сигналы, а реализация (тонкий стор в Presentation) отражает их в наблюдаемом
/// состоянии экрана. Через этот порт Application управляет ходом рана, ничего не
/// зная про SwiftUI/@Observable — правило зависимостей соблюдено.
@MainActor
public protocol RunOutput: AnyObject {
    /// Очередное событие потока — применить к транскрипту.
    func receive(event: AgentEvent)
    /// Поток закрылся без финального result-события.
    func runEndedWithoutResult()
    /// Ран отменён (задача потребления снята).
    func runCancelled()
    /// Поток упал ошибкой.
    func runFailed(error: Error)
}

/// Прикладная служба рана агента (слой Application). Оркестрирует порты
/// Domain: гоняет поток раннера и попутно выполняет политику автоимпорта сессии в
/// просмотрщик. Бизнес-правил сборки ленты здесь НЕТ — они в доменном агрегате
/// `Transcript`, куда события кладёт сток `RunOutput`.
///
/// `@MainActor`: тот же актор, что у стора-стока и у `openSessionNow` (бьёт в AppKit). Как
/// `@MainActor` его бин confined — вне жадной преинстанциации — и строится через
/// `MainActor.assumeIsolated` при resolve на главном акторе.
///
/// `@ApplicationService`, а не `@UseCase`: сценариев тут ДВА (`run(command:into:)` и
/// `openResult(sessionID:)`), а `@UseCase` — служба ровно с одной публичной операцией. Контейнер
/// собирает её сам, внедряя порты `AgentRunner`/`AgentSessionOpening`; резолв по конкретному типу
/// (порта у службы нет — `RunStore` зависит от `RunService` напрямую).
@MainActor
@ApplicationService
public final class RunService {
    private let runner: AgentRunner
    private let sessionOpener: AgentSessionOpening

    public init(runner: AgentRunner, sessionOpener: AgentSessionOpening) {
        self.runner = runner
        self.sessionOpener = sessionOpener
    }

    /// Запустить ран и прокачивать его прогресс в `output`. Возвращает задачу
    /// потребления — вызывающий держит её и отменяет при остановке; отмена штатно
    /// рвёт стрим (в адаптере — SIGINT ребёнку). Задача напрямую итерирует поток
    /// раннера, без обёрток, поэтому семантика отмены не меняется.
    public func run(command: RunCommand, into output: RunOutput) -> Task<Void, Never> {
        let stream = runner.stream(
            prompt: command.prompt,
            projectDirectory: command.projectDirectory,
            permissionMode: command.permissionMode
        )
        return Task { [weak output, sessionOpener] in
            do {
                for try await event in stream {
                    // Политика автоимпорта: сессию в просмотрщик — «выстрелил и забыл»,
                    // чтобы ожидание файла транскрипта не тормозило поток событий.
                    if case .sessionStarted(let start) = event, command.opensSessionInViewer {
                        Task {
                            await sessionOpener.openSession(
                                sessionID: start.sessionID, projectDirectory: start.projectDirectory)
                        }
                    }
                    output?.receive(event: event)
                }
                output?.runEndedWithoutResult()
            } catch is CancellationError {
                output?.runCancelled()
            } catch {
                output?.runFailed(error: error)
            }
        }
    }

    /// Открыть завершённую сессию результата в просмотрщике (кнопка на карточке
    /// результата, когда транскрипт заведомо на диске).
    public func openResult(sessionID: String) {
        sessionOpener.openSessionNow(sessionID: sessionID)
    }
}
