/**
 Раздел рейла.

 Восемь незнакомых пиктограмм без единого слова — ребус: рейл называл разделы
 только всплывающей подсказкой, то есть тому, кто уже знает, куда наводить.
 Под каждым знаком стоит слово. Заплачено 32 px канваса, выручено — весь
 каркас стал называть себя сам.

 ДОЛГ: знаки взяты ближайшими SF Symbols; свой спрайт эталона приедет
 вместе с разбором экрана на части.
 */
public enum BoardSection: String, CaseIterable, Identifiable, Sendable {
    case inbox
    case board
    case review
    case tasks
    case projects
    case insights
    case skills
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox: "Инбокс"
        case .board: "Канбан"
        case .review: "Ревью"
        case .tasks: "Задачи"
        case .projects: "Проекты"
        case .insights: "Аналитика"
        case .skills: "Навыки"
        case .settings: "Настройки"
        }
    }

    public var symbol: String {
        switch self {
        case .inbox: "tray"
        case .board: "rectangle.split.3x1"
        case .review: "text.magnifyingglass"
        case .tasks: "list.bullet"
        case .projects: "folder"
        case .insights: "chart.line.uptrend.xyaxis"
        case .skills: "square.inset.filled"
        case .settings: "slider.horizontal.3"
        }
    }

    /// Настройки стоят отдельно, прижатые к низу рейла: это не восьмой раздел
    /// продукта, а выход из него.
    public static var workSections: [BoardSection] { allCases.filter { $0 != .settings } }
}
