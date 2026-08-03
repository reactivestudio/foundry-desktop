import Core
import SwiftUI

/**
 Геометрия главного экрана — числами эталона, а не на глаз.

 Источник — `design/candidates/main-screen-board.md` и собранный из него кадр;
 все значения СНЯТЫ пробой Chrome с готовой страницы, а не переписаны из CSS
 (правило доски: рукописному числу рядом с вычислимым не верить, а сверять).
 Что не выражается токеном `Token.Space`/`Token.Radius`, стоит здесь именем,
 а не тройкой в теле вью.

 Порядок величин — закон, и он проверяется здесь же, а не в комментарии:
 поле карточки < зазор между карточками < зазор между колонками < поле плиты
 < шов перед «Готово». Поле, равное рву вокруг объекта, растворяет объект
 в однородной сетке.
 */
enum BoardMetrics {
    // MARK: Окно и плиты

    /// Поле окна по бокам и снизу; сверху его нет — там титлбар, и он стоит
    /// ВНУТРИ этого поля: светофор занимает ровно плиту рейла.
    static let windowPadding = Token.Space.step5
    /// Высота титлбара со светофором.
    static let titlebarHeight: CGFloat = 44
    /// Зазор между тремя плитами окна: рейлом, сайдбаром и канвасом.
    static let plateGap = Token.Space.step4
    /// Рейл: восемь разделов знаком и словом.
    static let railWidth: CGFloat = 76
    /// Сайдбар: срез и список проектов. Он же пульт фильтров.
    static let sidebarWidth: CGFloat = 214
    /// Отступ заголовка окна от кромки плит: полоса светофора шириной с рейл
    /// плюс зазор между плитами. Заголовок встаёт на флаг сайдбара.
    static var titleLeading: CGFloat { railWidth + plateGap }

    // MARK: Рейл

    static let railPaddingVertical = Token.Space.step4
    static let railItemGap = Token.Space.step1
    static let railItemWidth: CGFloat = 60
    static let railItemPaddingTop: CGFloat = 7
    static let railItemPaddingBottom: CGFloat = 6
    static let railItemRadius: CGFloat = 9
    /// Знак и слово под ним.
    static let railIconGap: CGFloat = 3
    static let railIconSide: CGFloat = 17

    // MARK: Сайдбар

    static let sidebarPaddingVertical = Token.Space.step4
    static let sidebarPaddingHorizontal = Token.Space.step2
    /// Между «Срезом» и «Проектом»: соседние секции пульта.
    static let sidebarSectionGap = Token.Space.step5
    /// Внутри секции строки стоят почти вплотную — они один список.
    static let sidebarRowGap: CGFloat = 2
    /// Подпись секции отстоит от своих строк на поле пульта.
    static let sidebarCaptionGap = Token.Space.step2

    // MARK: Доска

    /// Ширина дорожки — свойство пайплайна, а не окна: одна и та же карточка
    /// обязана быть одного размера и на доске из трёх стадий, и из десяти.
    static let laneWidth: CGFloat = 124
    /// Зазор между колонками.
    static let laneGap = Token.Space.step4
    /// Поле плиты канваса по бокам: доска стоит на флаге канваса.
    static let platePadding = Token.Space.step5
    /// Поле доски сверху и снизу (по бокам его держит плита).
    static let boardPaddingTop = Token.Space.step5
    static let boardPaddingBottom = Token.Space.step4
    /// Строка среза уже отбила доску сверху — доске остаётся зазор между плитами.
    static let boardPaddingUnderNote = Token.Space.step4
    /// Пустая дорожка перед «Готово». Видимый шов — она плюс два зазора: 52.
    /// «Готово» не девятая стадия, а корзина, и шов обязан быть шире зазора
    /// между стадиями — внутреннее меньше внешнего.
    static let seamLane: CGFloat = 20
    static var visibleSeam: CGFloat { seamLane + 2 * laneGap }
    /// Шапка колонки: подпись, под ней число, и отбивка до первой карточки.
    static let columnHeadGap: CGFloat = 1
    static let columnHeadPaddingBottom: CGFloat = 3
    /// Сноска свёртки отбита от стопки ВДВОЕ против зазора между карточками:
    /// отстоящая ровно на зазор, она секунду читалась ещё одной карточкой.
    static let foldNoteGap = Token.Space.step5

    // MARK: Карточка

    static let cardPadding = Token.Space.step2
    /// Зазор МЕЖДУ карточками в стопке.
    static let cardGap = Token.Space.step3
    /// Зазор ВНУТРИ карточки: заголовок → чип. Он равен зазору между
    /// карточками намеренно, потому что карточка растёт по содержимому:
    /// жёсткая высота выравнивала ряды, которые на канбане ничего не значат
    /// (вторая карточка Questions и вторая карточка PR не связаны ничем),
    /// а платой была дыра ВНУТРИ карточки больше, чем зазор МЕЖДУ ними.
    static let cardInnerGap = Token.Space.step3
    static let cardRadius = Token.Radius.large
    /// Заголовок обрывается на третьей строке: дальше карточка перестаёт быть
    /// карточкой и становится абзацем.
    static let cardTitleLineLimit = 3
    /// Высота строки подписи — из неё считается высота пункта рейла.
    static let captionLineHeight = Token.Typography.caption.leading

    // MARK: Полоса пайплайнов

    static let pipeBarPaddingTop = Token.Space.step4
    static let pipeBarGap = Token.Space.step5
    /// Внутри вкладки шаги разведены: имя → счётчик 4, счётчик → «8 стадий» 16.
    /// Два числа в четырёх пунктах друг от друга читались одной величиной.
    static let pipeTabGap = Token.Space.step1
    static let pipeMetaGap = Token.Space.step4

    // MARK: Минимум окна

    /// На минимуме уступает только канвас: рейл и сайдбар неделимы (значок
    /// с подписью и строка списка своей ширины), а дорожка — константа.
    /// Три стадии, шов и «Готово» — меньше доска не бывает.
    static let minimumStages = 3
    static func canvasWidth(stages: Int) -> CGFloat {
        2 * platePadding + CGFloat(stages + 1) * laneWidth + seamLane
            + CGFloat(stages + 1) * laneGap
    }
    static func windowWidth(stages: Int) -> CGFloat {
        2 * windowPadding + railWidth + plateGap + sidebarWidth + plateGap
            + canvasWidth(stages: stages)
    }
    static var minimumWindowWidth: CGFloat { windowWidth(stages: minimumStages) }
    /// Кадр эталона: восемь стадий, шов и корзина видны целиком, без прокрутки.
    static var etalonWindowWidth: CGFloat { windowWidth(stages: 8) }
    static let etalonWindowHeight: CGFloat = 672
    /// Высота пункта рейла: поле, знак, зазор, слово, поле.
    static var railItemHeight: CGFloat {
        railItemPaddingTop + railIconSide + railIconGap + captionLineHeight + railItemPaddingBottom
    }
    /// Минимум по высоте диктует рейл: восемь разделов не делятся, а девятый
    /// («Настройки») отбит от них не меньше чем зазором между плитами.
    static var minimumWindowHeight: CGFloat {
        titlebarHeight + windowPadding + 2 * railPaddingVertical
            + 8 * railItemHeight + 7 * railItemGap + plateGap
    }

    /// Порядок величин — закон, а не пожелание. Свободных значений шкалы между
    /// 4 и 12 нет, поэтому развести поля карточки по сторонам нельзя: поле
    /// обязано быть МЕНЬШЕ зазора, иначе карточка растворяется в сетке.
    static func checkLadder() -> Bool {
        cardPadding < cardGap && cardGap < laneGap && laneGap < platePadding
            && platePadding < visibleSeam
    }

}
