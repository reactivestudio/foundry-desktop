import SwiftUI

/// Тюнер тени карточек/панелей. Модель «spread + blur»: залитый чёрный силуэт,
/// вынесенный за кромку на `spread` px во все стороны, с размытием края на `blur` px.
enum SetupShadow {
    static let spread: CGFloat = 80  // вынос за кромку во все стороны, px
    static let blur: CGFloat = 80  // размытие края, px (0 = чёткая граница)
    static let opacity: Double = 0.8  // прозрачность ВСЕГО слоя (после уплощения)
    static let color = Color.black
}
