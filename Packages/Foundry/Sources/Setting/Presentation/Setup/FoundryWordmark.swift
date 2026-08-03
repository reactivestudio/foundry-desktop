import AppKit
import SwiftUI

// MARK: - Логотип «Foundry AI»

/// Вордмарк + лейбл-знак «AI» единым компонентом (13, глава 9). Все внутренние
/// меры — в em от кегля знака: на базовом 34 попиксельно равны макету, на другом
/// кегле знак масштабируется целиком. Знак неделим — вордмарк без лейбла не живёт.
struct FoundryWordmark: View {
    var logoSize: CGFloat = 34
    private var em: CGFloat { logoSize / 34 }

    var body: some View {
        HStack(alignment: .top, spacing: 9 * em) {
            Text("Foundry")
                .font(.system(size: logoSize, weight: .bold))
                .tracking(-0.02 * logoSize)
                .foregroundStyle(SetupStyle.Text.primary)
            aiLabel
                // к верхней линии литер вордмарка, не к строке
                .padding(.top, 5 * em)
        }
        .fixedSize()
    }

    private var aiLabel: some View {
        let labelSize: CGFloat = 10 * em  // кегль лейбла
        // Скругление — гиперэллипс (Squircle, суперэллипс n=4), радиус на ПОТОЛКЕ:
        // Squircle клампит угол в половину меньшей стороны, а меньшая здесь — высота
        // labelSize + 0.25 + 0.27 = 1.52·labelSize, значит фактический угол =
        // 0.76·labelSize. Радиус задан с запасом и всегда сидит на потолке — торцы
        // остаются максимально круглыми при любой высоте плашки, меняется лишь пропорция.
        let radius: CGFloat = 1.0 * labelSize
        // Поля от кегля лейбла. Низ чуть больше верха (+0.07) — у заглавных нет
        // нижних выносов, при равных полях они смотрятся просевшими.
        let insets = EdgeInsets(
            top: 0.25 * labelSize, leading: 0.45 * labelSize,
            bottom: 0.27 * labelSize, trailing: (0.5 - 0.06) * labelSize)
        let plateGradient = LinearGradient(
            stops: [
                .init(color: SetupStyle.amberTop, location: 0),
                .init(color: SetupStyle.amberMid, location: 0.55),
                .init(color: SetupStyle.amberBottom, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        let highlight = LinearGradient(
            colors: [.white.opacity(0.45), .clear],
            startPoint: .top, endPoint: .bottom)
        // Радиус уже на потолке (= половина высоты), расти ему некуда. Круглее делаем
        // ПОКАЗАТЕЛЕМ суперэллипса: n=3 вместо канонных 4 — угол ближе к дуге
        // окружности, размеры плашки при этом не меняются.
        let shape = Squircle(cornerRadius: radius, exponent: 3)
        let plate =
            shape
            .fill(plateGradient)
            .overlay(shape.strokeBorder(highlight, lineWidth: max(0.5, 0.05 * labelSize)))

        return Text("AI")
            .font(.system(size: labelSize, weight: .bold))
            .tracking(0.06 * labelSize)
            .foregroundStyle(SetupStyle.bg)
            // свет принадлежит буквам: 1px освещённой нижней губки выреза
            .shadow(color: .white.opacity(0.35), radius: 0, y: 0.1 * labelSize)
            // `line-height: 1` канона. У SwiftUI-Text бокс равен ЛИНЕЙНОЙ высоте
            // шрифта (~1.19·s у SF), и поля отсчитывались от неё — плашка выходила
            // на ~19% выше макетной: зазоры до текста больше, а гиперэллипс на
            // вытянутом боксе терял характер. Фиксируем бокс ровно в кегль.
            .frame(height: labelSize)
            .padding(insets)
            .background(plate)
    }
}
