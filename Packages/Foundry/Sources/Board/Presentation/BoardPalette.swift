import Core
import SwiftUI

/**
 Цвета главного экрана. Почти всё берётся из `Token` — здесь только то,
 чего в каноне нет ИМЕНЕМ, и каждое такое значение снято пробой с эталона.

 Правило экрана: цвет приходит СПЛОШНЫМ чипом малой площади со словом внутри,
 а не полупрозрачной заливкой на большой площади. Альфа-заливка цветом поверх
 почти чёрного даёт грязь (янтарь 11 % на базе читается оливой), поэтому
 поверхности выше базы обесцвечены (`Token.Background`), а цвет живёт только
 в чипе. Все заливки чипов доведены выше 4.5:1 — это и есть та поправка
 к 08-controls, которую эталон предъявляет канону.
 */
enum BoardPalette {
    /// Фон окна: то, что видно между плитами.
    static let window = Token.Background.base
    /// Плита — рейл, сайдбар, канвас.
    static let plate = Token.Background.surface
    /// Карточка доски и всё, что на плите стоит.
    static let card = Token.Background.raised
    /// Поверх всего: плавающий инспектор и тост. Друг над другом не бывают.
    static let overlay = Token.Background.overlay

    /// Подъём карточки под курсором. Это НЕ пятая ступень поверхности:
    /// ступеней ровно четыре, а подъём — состояние, и он выше overlay
    /// намеренно, потому что живёт над своей плитой, а не над экраном.
    static let cardHover = Color(hexValue: 0x2A2A31)
    /// Нажатие плоскому знаку гасить нечем — в покое у него заливки нет,
    /// поэтому оно уводит его НИЖЕ плиты, а не выше.
    static let flatPressed = Color(white: 0, opacity: 0.28)
    /// Наведение на пункт пульта — рейла и сайдбара разом: правило одно.
    static let flatHover = Color(white: 1, opacity: 0.05)
    /// Выбранный пункт пульта. Цвет тут не нужен: позиция и вес уже сказали всё.
    static let flatSelected = Color(white: 1, opacity: 0.13)

    /// Свет по кромке карточки. На почти чёрном отделяет не темнота, а СВЕТ:
    /// тени нечего гасить, когда под ней уже почти чёрное.
    static let edgeLight = Color(white: 1, opacity: 0.09)

    // MARK: Чипы состояний

    /// «Ждёт» — ваш ход. Янтарь сплошной заливкой с тёмной надписью.
    static let chipWait = Token.Semantic.warning
    static let chipWaitInk = Color(hexValue: 0x17130A)
    /// «Упало»/«встало» — ничей ход. Коралл эталона темнее `Semantic.error`
    /// ровно настолько, чтобы тёмная надпись на нём взяла порог.
    static let chipStop = Color(hexValue: 0xFF8A73)
    static let chipStopInk = Color(hexValue: 0x2B0C05)
    /// «Идёт» — ход агента. Цвета не несёт вовсе: работа агента это норма,
    /// а не событие, и красить её значит звать на помощь там, где всё хорошо.
    static let chipLive = Color(hexValue: 0x2E2E36)
    static let chipLiveInk = Color(hexValue: 0xC9C9CC)
    /// «Принят» и «нет связи» — самая тихая плашка, на ступени overlay.
    static let chipMuted = Token.Background.overlay
    static let chipMutedInk = Color(hexValue: 0x9A9AA0)
}
