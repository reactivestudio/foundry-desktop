import Foundation

/**
 Мир доски на фикстурах — ровно тот, что стоит на эталоне
 (`design/candidates/main-screen-board.md`).

 Здесь он временно и целиком: сущностей у доски пока нет, а экран уже принят,
 и каркас надо на чём-то поднимать. Когда придёт настоящий `Change`, эта папка
 умирает вся — она для того и лежит в презентации, отдельным каталогом.

 МИР ОДИН НА ВСЕ ВИДЫ. На эталоне это правило далось дорого: пока каждый кадр
 считал по-своему, «foundry-desktop» был то 18, то 2, то 42, а «Все проекты»
 гуляли 33 / 55 / 17 — каждый кадр был прав внутри себя, а разворот врал.
 Поэтому числа здесь НЕ пишутся рукой там, где их можно вывести: срез
 считается по доске, счётчик «Все проекты» — по списку.
 */
enum BoardFixture {
    /// Сколько change'ей в каком пайплайне у какого проекта.
    /// Рукой пишутся только чужие проекты — их доску никто не видит.
    static let world: [(project: String, pipelines: [(String, Int)])] = [
        ("foundry-desktop", [("Фича в одном сервисе", 18), ("Баг", 3), ("Инцидент", 1)]),
        ("crispy-core", [("Хотфикс", 2), ("Фича в нескольких сервисах", 7)]),
        ("monorepo", [("Фича в одном сервисе", 42)]),
        ("memory-vault", [("Фича в одном сервисе", 4)]),
        ("books", [("Фича в одном сервисе", 2)]),
        ("дизайн-система", []),
    ]

    /// Стадии пайплайнов — по `docs/reference/ui/domain-model.md`.
    static let stages: [String: [String]] = [
        "Фича в одном сервисе":
            ["Questions", "Research", "Design", "Structure", "Plan", "Worktree", "Implement", "PR"],
        "Фича в нескольких сервисах":
            [
                "Questions", "Research", "Design", "Contracts", "Structure", "Plan",
                "Worktree", "Implement", "Integration", "PR",
            ],
        "Баг": ["Repro", "Diagnose", "Fix", "Test", "PR"],
        "Хотфикс": ["Repro", "Fix", "Ship"],
        "Инцидент": ["Triage", "Mitigate", "RCA", "Postmortem"],
    ]

    /// Порядок вкладок ФИКСИРОВАН — как и порядок проектов.
    static let pipelineOrder = [
        "Фича в одном сервисе", "Фича в нескольких сервисах",
        "Баг", "Хотфикс", "Инцидент",
    ]

    /// В корзине «Готово» принято 12, показаны две последние.
    static let acceptedTotal = 12

    /// Доска выбранного пайплайна выбранного проекта.
    ///
    /// Порядок карточек в колонке — по времени без движения, сверху самые
    /// давние. Порядок, который не заявлен и не соблюдается, читатель всё равно
    /// ищет — и находит несуществующий. Корзина живёт по другому правилу
    /// и говорит об этом словом: сверху последнее принятое.
    static let board: [StageColumn] = [
        StageColumn(
            "Questions",
            [
                ChangeCard("Скоупы бинов Spark", .waiting, "ждёт 26 ч"),
                ChangeCard("Нотч-хелпер", .waiting, "ждёт 3 ч"),
                ChangeCard("Экспорт диффа в печатной палитре", .waiting, "ждёт 25 мин"),
            ]),
        StageColumn(
            "Research",
            [
                ChangeCard("Liquid Glass", .running, "идёт 18 мин"),
                ChangeCard("APCA против WCAG", .running, "идёт 4 мин"),
            ]),
        StageColumn(
            "Design",
            [
                ChangeCard("Стадии CRISPY", .waiting, "ждёт 1 ч"),
                ChangeCard("Пустые состояния доски", .running, "идёт 20 мин"),
                ChangeCard("Токены тёмной темы", .waiting, "ждёт 12 мин"),
                ChangeCard("Пустая доска нового проекта", .running, "идёт 2 мин"),
            ]),
        StageColumn(
            "Structure",
            [
                ChangeCard("Контекст доски", .stalled, "встало 6 ч"),
                ChangeCard("Хранилище инбокса", .running, "идёт 8 с"),
            ]),
        StageColumn(
            "Plan",
            [
                ChangeCard("Слоты агентов и лимиты", .running, "идёт 40 мин")
            ]),
        StageColumn(
            "Worktree",
            [
                ChangeCard("Инспектор по требованию", .running, "идёт 12 с")
            ]),
        StageColumn(
            "Implement",
            [
                ChangeCard("Орб-лоадер", .running, "идёт 6 ч"),
                ChangeCard("Тост отмены", .stalled, "встало 1 ч"),
                ChangeCard("Горячие клавиши инспектора", .running, "идёт 8 мин"),
            ]),
        StageColumn(
            "PR",
            [
                ChangeCard("Контраст по APCA", .failed, "упало 3 ч"),
                ChangeCard("Свёртка колонки «Готово»", .waiting, "ждёт 2 ч"),
            ]),
        StageColumn(
            "Готово",
            [
                ChangeCard("Онбординг", .accepted, "вчера, 14:32"),
                ChangeCard("Дизайн-канон", .accepted, "пт, 11:20"),
            ], isBin: true, binTotal: acceptedTotal),
    ]

    // MARK: Выведенное — не написанное рукой

    /// Стадии без корзины: «Готово» — не стадия, а корзина.
    static var stageColumns: [StageColumn] { board.filter { !$0.isBin } }

    /// Сколько change'ей в работе. Ровно то, что видно на доске: пересчитав
    /// чипы, читатель обязан получить это же число.
    static var inWorkCount: Int { stageColumns.reduce(0) { $0 + $1.cards.count } }

    /// Срез — три состояния теми же словами, что и чипы на карточках.
    static var slice: (waiting: Int, running: Int, nobody: Int) {
        var waiting = 0, running = 0, nobody = 0
        for column in stageColumns {
            for card in column.cards {
                switch card.move {
                case .waiting: waiting += 1
                case .running: running += 1
                case .stalled, .failed: nobody += 1
                case .accepted: break
                }
            }
        }
        return (waiting, running, nobody)
    }

    /// Счётчик проекта считает ПРОЕКТ, а не доску: работа за другими вкладками
    /// — тоже работа. Разницу между ним и суммой среза читатель закрывает
    /// не верой, а сложением: числа вкладок стоят на самих вкладках.
    static func projectTotal(_ project: String) -> Int {
        world.first { $0.project == project }?.pipelines.reduce(0) { $0 + $1.1 } ?? 0
    }

    /// Строки среза для сайдбара. `isOffline` — потеряна связь с ядром:
    /// прочерк ставится ТОЛЬКО у хода агента. Сколько change'ей ждут вас
    /// и сколько встало, видно по снапшоту — янтарные и коралловые чипы
    /// никуда с доски не делись, и спорить с тем, что читатель видит, нельзя.
    static func sliceRows(isOffline: Bool = false) -> [SidebarRow] {
        let counts = slice
        return [
            SidebarRow("Всё в работе"),
            SidebarRow("Ваш ход", String(counts.waiting)),
            SidebarRow(
                isOffline ? "Нет связи" : "Ход агента",
                isOffline ? "—" : String(counts.running)),
            SidebarRow("Ничей ход", String(counts.nobody)),
        ]
    }

    /// Строки списка проектов. «Все проекты» выводится, а не пишется рукой.
    static var projectRows: [SidebarRow] {
        let total = world.reduce(0) { $0 + projectTotal($1.project) }
        return [SidebarRow("Все проекты", SidebarRow.number(total))]
            + world.map { SidebarRow($0.project, SidebarRow.number(projectTotal($0.project))) }
    }

    /// Вкладки пайплайнов выбранного проекта.
    static func pipelineTabs(project: String) -> [PipelineTab] {
        let counts = world.first { $0.project == project }?.pipelines ?? []
        return pipelineOrder.map { name in
            PipelineTab(
                name, stages[name] ?? [],
                counts.first { $0.0 == name }?.1 ?? 0)
        }
    }
}
