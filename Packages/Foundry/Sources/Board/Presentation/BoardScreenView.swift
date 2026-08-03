import Core
import SwiftUI

/**
 Главный экран — одно окно со многими вариациями, а не много окон.

 Каркас: рейл разделов · сайдбар-пульт · канвас · инспектор по требованию.
 Сайдбар не раскрывается из рейла, а МЕНЯЕТ содержимое вместе с разделом;
 он же пульт фильтров. Дефолт канваса — доска change'ей, где колонки это
 стадии пайплайна.

 Сущностей у контекста пока нет: экран принят эталоном раньше, чем домен,
 и весь мир берётся из `BoardFixture`. Состояние выбора живёт здесь, в `@State`
 — не потому что так правильно, а потому что стору пока нечем владеть.
 Когда придёт домен, отсюда уедет и то, и другое.

 Один раздел рейла отдан ГОСТЮ — виду из другого контекста, который сшивает
 сюда корень композиции. Так консоль рана остаётся доступной, а доска про
 неё по-прежнему ничего не знает: граница контекстов сторожится компилятором.
 */
public struct BoardScreenView<Guest: View>: View {
    /// Раздел, под которым живёт гость.
    private let guestSection: BoardSection
    private let guest: Guest

    @State private var section: BoardSection = .board
    @State private var slice = "Всё в работе"
    @State private var project = "foundry-desktop"
    @State private var pipeline = "Фича в одном сервисе"

    public init(guestSection: BoardSection, @ViewBuilder guest: () -> Guest) {
        self.guestSection = guestSection
        self.guest = guest()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Титлбар стоит ВНУТРИ поля окна, а не поверх него: только так
            // светофор занимает ровно плиту рейла, а заголовок встаёт
            // на флаг сайдбара.
            BoardTitlebarView(project: project)
            HStack(alignment: .top, spacing: BoardMetrics.plateGap) {
                BoardRailView(selection: $section)
                BoardSidebarView(
                    sliceRows: BoardFixture.sliceRows(),
                    projectRows: BoardFixture.projectRows,
                    selectedSlice: $slice,
                    selectedProject: $project
                )
                canvas
            }
        }
        .padding(.horizontal, BoardMetrics.windowPadding)
        .padding(.bottom, BoardMetrics.windowPadding)
        .frame(
            minWidth: BoardWindowFrame.minimum.width,
            minHeight: BoardWindowFrame.minimum.height
        )
        .background(BoardPalette.window)
        // Титлбар у экрана СВОЙ и вдвое выше системного: без этого SwiftUI
        // отступал от системной полосы 28 пунктов, и весь экран — светофор,
        // плиты, доска — уезжал на них вниз, а собственный титлбар вставал
        // второй строкой под системным.
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private var canvas: some View {
        if section == .board {
            BoardCanvasView(
                tabs: BoardFixture.pipelineTabs(project: project),
                columns: columns,
                sliceNote: sliceNote,
                selectedPipeline: $pipeline
            )
        } else if section == guestSection {
            guest
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BoardPalette.plate)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: Token.Radius.extraLarge,
                        style: .continuous))
        } else {
            BoardStubView(section: section)
        }
    }

    /// Срез не подсвечивает карточки и не крутит доску к ним: он убирает
    /// с доски всё остальное, оставляя колонки НА МЕСТЕ. Дорожки той же
    /// ширины, стадии в том же порядке — глазу не нужно заново искать,
    /// где Design; меняется только населённость колонок.
    private var columns: [StageColumn] {
        guard let move = sliceMove else { return BoardFixture.board }
        return BoardFixture.board.map { column in
            column.filtered { card in
                move == .stalled ? card.move.isNobodysMove : card.move == move
            }
        }
    }

    private var sliceMove: ChangeMove? {
        switch slice {
        case "Ваш ход": .waiting
        case "Ход агента": .running
        case "Ничей ход": .stalled
        default: nil
        }
    }

    private var sliceNote: SliceNote? {
        guard sliceMove != nil else { return nil }
        let shown = columns.filter { !$0.isBin }.reduce(0) { $0 + $1.cards.count }
        return SliceNote(name: "«\(slice)»", shown: shown, total: BoardFixture.inWorkCount)
    }
}
