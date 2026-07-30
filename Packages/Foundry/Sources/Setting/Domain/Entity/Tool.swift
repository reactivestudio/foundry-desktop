import Core

/**
 Агрегат инструмента связки — второй корень BC `Setting`. Один тип на все инструменты,
 различает их `kind`: агентский CLI, плагин агента, свой `foundry` CLI. Инстансов столько,
 сколько инструментов знает приложение (`known()`), и у каждого свой стабильный id.

 Репозитория у него нет и не будет: состояние инструмента — установлен ли, какой версии —
 принадлежит системе пользователя, а не нам. Агрегат РЕКОНСТИТУИРУЕТСЯ из ответа порта
 `ToolGateway` при каждом обновлении экрана; сохранять его значило бы держать копию чужой
 истины, которая устареет в тот же день. Что действительно наше — ВЫБОР агента — лежит в
 `Preference` (группа `Agent`), потому что это настройка, а не факт о системе.

 Оттого и команда ровно одна: принять свежий ответ системы.
 */
public final class Tool: AggregateRoot<ToolId> {
    public let kind: ToolKind
    public private(set) var installation: Installation

    private init(id: ToolId, kind: ToolKind, installation: Installation) {
        self.kind = kind
        self.installation = installation
        super.init(id: id)
    }

    public static func of(
        id: ToolId,
        kind: ToolKind,
        installation: Installation = .missing
    ) -> Tool {
        Tool(id: id, kind: kind, installation: installation)
    }

    /**
     Инструменты, которыми пользуется Foundry, — состав связки на сегодня. Фабрика отдаёт
     СВЕЖИЕ инстансы каждому вызову: агрегат мутабелен, и общий на всех экземпляр стал бы
     разделяемым состоянием.
     */
    public static func known() -> [Tool] {
        [
            Tool.of(id: .claudeCode, kind: .agentCli),
            Tool.of(id: .codexCli, kind: .agentCli),
            Tool.of(id: .geminiCli, kind: .agentCli),
            Tool.of(id: .claudePlugin, kind: .agentPlugin),
            Tool.of(id: .foundryCli, kind: .foundryCli),
        ]
    }

    /// Принять свежий ответ системы об установленности.
    public func change(installation: Installation) {
        mutate {
            self.installation = installation
        }
    }

    public var isInstalled: Bool {
        installation.isInstalled
    }
}
