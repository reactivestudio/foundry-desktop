import SparkIoC

/**
 Прикладная служба инструментов связки (слой Application). Как и у разрешений, транзакции
 здесь нет: состояние инструментов принадлежит системе пользователя. Служба реконституирует
 известные агрегаты (`Tool.known()`) свежими ответами порта и отдаёт их наружу.

 `@MainActor`: службу зовёт стор с главного актора, а показ инструкции упирается в AppKit.
 `@ApplicationService` — операций две; порта у службы нет, её резолвят по конкретному типу.
 */
@MainActor
@ApplicationService
public final class ToolService {
    private let gateway: ToolGateway
    private let instructions: InstallInstructionOpening

    public init(gateway: ToolGateway, instructions: InstallInstructionOpening) {
        self.gateway = gateway
        self.instructions = instructions
    }

    /**
     Все инструменты связки со свежим состоянием установки. Спрашиваем ПАРАЛЛЕЛЬНО: за
     каждым ответом поход на диск и запуск чужого процесса (`--version`), и очередь из
     пяти таких вопросов складывалась бы в заметную паузу на входе в экран. Порядок
     инструментов при этом остаётся доменным — он задан `Tool.known()`, а не тем, кто
     ответил первым.
     */
    public func tools() async -> [Tool] {
        let tools = Tool.known()
        let installations = await withTaskGroup(of: (ToolId, Installation).self) { group in
            for tool in tools {
                let id = tool.id
                group.addTask { [gateway] in (id, await gateway.inspect(tool: id)) }
            }

            var answers: [ToolId: Installation] = [:]
            for await (id, installation) in group {
                answers[id] = installation
            }

            return answers
        }
        for tool in tools {
            tool.change(installation: installations[tool.id] ?? .missing)
        }

        return tools
    }

    /// Показать, как поставить инструмент. Устанавливать приложение не берётся — см. порт.
    public func openInstructions(for tool: ToolId) {
        instructions.openInstructions(for: tool)
    }
}
