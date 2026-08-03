import Core
import SwiftUI

/**
 Карточка change'а: заголовок и чип состояния. Больше на ней нет ничего.

 Знака вида на карточке нет: он дублировал префикс ветки (feat/, docs/,
 refactor/), который виден всегда, и при этом отъедал 18 пунктов у заголовка
 в дорожке шириной 124 — «Инспектор по требованию» срезало на последней букве.
 Ветки тоже нет: на восемнадцати карточках она была транслитерацией
 собственного заголовка. Обе живут в инспекторе, откуда их копируют.

 Рост — ПО СОДЕРЖИМОМУ. Жёсткая высота выравнивала ряды сквозь колонки, но
 ряды на канбане ничего не значат: вторая карточка Questions и вторая
 карточка PR не связаны ничем. Выравнивание оказалось ради выравнивания,
 а платой была дыра ВНУТРИ карточки больше, чем зазор МЕЖДУ карточками.

 Бордера в покое нет вовсе — обводка на этом экране означает выбор или
 внимание, и когда обведено всё, она не означает ничего. Наведение поднимает
 карточку конечной светлотой (а не альфой: разрыв обязан быть одинаков на
 любой плите) и добавляет свет по верхней кромке — на почти чёрном отделяет
 не темнота, а свет, тени тут нечего гасить.
 */
struct ChangeCardView: View {
    let card: ChangeCard
    /// На первой стадии пайплайна ожидание значит «агент спросил».
    let isFirstStage: Bool
    /// В корзине заголовок тише: принятое видно, но не спорит с работой.
    let isAccepted: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: BoardMetrics.cardInnerGap) {
            Text(card.title)
                .typography(Token.Typography.bodyEm)
                .foregroundStyle(isAccepted ? Token.Text.secondary : Self.titleInk)
                .lineLimit(BoardMetrics.cardTitleLineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            StateChipView(move: card.move, text: card.sinceText, isAsking: isFirstStage)
        }
        .padding(BoardMetrics.cardPadding)
        .frame(width: BoardMetrics.laneWidth, alignment: .topLeading)
        .background(isHovered ? BoardPalette.cardHover : BoardPalette.card)
        .overlay(alignment: .top) {
            if isHovered {
                Rectangle().fill(BoardPalette.edgeLight).frame(height: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BoardMetrics.cardRadius, style: .continuous))
        .contentShape(Rectangle())
        .animation(AppMotion.hover(isHovered), value: isHovered)
        .onHover { isHovered = $0 }
    }

    /// Заголовок карточки на полступени ниже основной ступени текста: он стоит
    /// на поднятой поверхности, где чистая ступень звенит.
    private static let titleInk = Color(white: 1, opacity: 0.93)
}
