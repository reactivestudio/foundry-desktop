import Observation
import SparkIoC

/**
 Стор инструментов связки — третий контроллер презентационного слоя BC `Setting`. Как и
 `PermissionStore`, он ничего не меняет: инструменты ставит пользователь, приложение лишь
 замечает установленность и умеет показать инструкцию.

 Наружу торчат `Installation` (иммутабельный VO), а сами агрегаты приватны — вью не должно
 получить мутабельный корень и менять состояние мимо системы. Снимок стартует пустым:
 спросить диск можно только асинхронно, а конструктор бина синхронный; до первого ответа
 инструменты показываются неустановленными, то есть с кнопкой Install, а не с ложной
 галочкой.
 */
@MainActor
@Observable
@Store
public final class ToolStore {
    /// Реконституированные агрегаты. Приватны намеренно (см. док типа): наружу — только VO.
    private var tools: [Tool] = []

    // Зависимость, не состояние: из наблюдения исключена (практики 03).
    @ObservationIgnored private let service: ToolService

    public init(service: ToolService) {
        self.service = service
    }

    /// Состояние установки инструмента; пока снимка нет — «не установлен».
    public func installation(of id: ToolId) -> Installation {
        tools.first { tool in tool.id == id }?.installation ?? .missing
    }

    /// Перечитать состояние у системы. Зовётся при появлении экрана и при возвращении в
    /// приложение: инструмент ставят снаружи, и узнать об этом можно только спросив заново.
    public func refresh() async {
        tools = await service.tools()
    }

    /// Показать инструкцию по установке — приложение не ставит инструменты за пользователя.
    public func openInstructions(for id: ToolId) {
        service.openInstructions(for: id)
    }
}
