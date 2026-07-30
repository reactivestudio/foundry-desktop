import Core
import SwiftUI

/// Обведённая галочка-кружок — единая форма факта на весь мастер (#ic-check):
/// кружок + галочка, монолиния, currentColor наследует цвет (везде sem-success).
struct CheckTick: View {
    var size: CGFloat = 13
    var color: Color = OB.success
    var body: some View {
        Canvas { context, canvasSize in
            let side = canvasSize.width
            let lineWidth = side * 1.75 / 24
            var circle = Path()
            circle.addEllipse(
                in: CGRect(
                    x: side * (12 - 9.2) / 24, y: side * (12 - 9.2) / 24,
                    width: side * 18.4 / 24, height: side * 18.4 / 24))
            context.stroke(circle, with: .color(color), style: StrokeStyle(lineWidth: lineWidth))
            var check = Path()
            check.move(to: CGPoint(x: side * 9 / 24, y: side * 12.3 / 24))
            check.addLine(to: CGPoint(x: side * 11 / 24, y: side * 14.3 / 24))
            check.addLine(to: CGPoint(x: side * 15.2 / 24, y: side * 9.6 / 24))
            context.stroke(
                check, with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}
