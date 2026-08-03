import Foundation

/**
 Колонка доски — стадия пайплайна или корзина «Готово».

 «Готово» не девятая стадия: change туда не переходит, а выбывает. Поэтому
 у неё свой шов, своя свёртка и своё правило порядка (сверху последнее
 принятое, а не самое давнее без движения).
 */
struct StageColumn: Identifiable, Sendable {
    let id: UUID
    let name: String
    let cards: [ChangeCard]
    /// Корзина принятого. Отделена швом и свёрнута до двух последних.
    let isBin: Bool
    /// Сколько принято всего: в корзине видны две последние, остальное свёрнуто.
    let binTotal: Int
    /// Сколько было в колонке ДО среза. nil — срез не применён.
    /// Под срезом шапка обязана называть обе величины: одно число вместо двух
    /// заставило бы читателя решить, что колонка опустела.
    let outOf: Int?

    init(
        _ name: String, _ cards: [ChangeCard], isBin: Bool = false, binTotal: Int = 0,
        outOf: Int? = nil, id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.cards = cards
        self.isBin = isBin
        self.binTotal = binTotal
        self.outOf = outOf
    }

    /// Число в шапке колонки: у стадии — сколько карточек, у корзины — сколько
    /// принято всего, включая свёрнутое. Иначе шапка спорила бы со свёрткой.
    /// Под срезом обе колонки показывают ровно то, что видно, а «всего»
    /// уходит в знаменатель рядом.
    var headerCount: Int {
        if outOf != nil { return cards.count }
        return isBin ? binTotal : cards.count
    }

    /// Сколько принятых свёрнуто под строкой «Ещё N принятых».
    /// Под срезом корзина не сворачивается: она и так показывает лишь срез.
    var foldedCount: Int {
        guard isBin, outOf == nil else { return 0 }
        return max(0, binTotal - cards.count)
    }

    /// Та же колонка, срезанная по ходу. Идентификатор сохраняется — иначе
    /// SwiftUI считает срезанную колонку другой и пересобирает её целиком,
    /// а колонки обязаны стоять на месте: меняется населённость, не порядок.
    func filtered(_ isIncluded: (ChangeCard) -> Bool) -> StageColumn {
        StageColumn(
            name, cards.filter(isIncluded), isBin: isBin, binTotal: binTotal,
            outOf: isBin ? binTotal : cards.count, id: id)
    }
}
