import Core

/**
 Настройки доступности приложения — VO агрегата `Preference`. Это НАШИ опции
 (уменьшить движение, крупнее шрифт, выше контраст), НЕ разрешение macOS Accessibility:
 то принадлежит системе (⌥Space, панель чёлки), живёт за Gateway и не хранится.
 Все поля булевы — меняются флипом `toggle…()` (возвращает новый VO).
 */
public struct Accessibility: ValueObject {
    public let reduceMotion: Bool
    public let largerText: Bool
    public let higherContrast: Bool

    private init(reduceMotion: Bool, largerText: Bool, higherContrast: Bool) {
        self.reduceMotion = reduceMotion
        self.largerText = largerText
        self.higherContrast = higherContrast
    }

    public static func of(
        reduceMotion: Bool = false,
        largerText: Bool = false,
        higherContrast: Bool = false
    ) -> Accessibility {
        Accessibility(reduceMotion: reduceMotion, largerText: largerText, higherContrast: higherContrast)
    }

    /// Переключить «уменьшить движение» — новый VO с инвертированным флагом.
    public func toggleReduceMotion() -> Accessibility {
        with(reduceMotion: !reduceMotion)
    }

    /// Переключить «крупнее шрифт» — новый VO с инвертированным флагом.
    public func toggleLargerText() -> Accessibility {
        with(largerText: !largerText)
    }

    /// Переключить «выше контраст» — новый VO с инвертированным флагом.
    public func toggleHigherContrast() -> Accessibility {
        with(higherContrast: !higherContrast)
    }

    /**
     Копия с точечной заменой полей (`nil` — оставить как есть). Приватная: повтор
     перечисления всех полей живёт в одном месте, наружу — только намерения `toggle…`.
     */
    private func with(
        reduceMotion: Bool? = nil,
        largerText: Bool? = nil,
        higherContrast: Bool? = nil
    ) -> Accessibility {
        Accessibility(
            reduceMotion: reduceMotion ?? self.reduceMotion,
            largerText: largerText ?? self.largerText,
            higherContrast: higherContrast ?? self.higherContrast
        )
    }
}
