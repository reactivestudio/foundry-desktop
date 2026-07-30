import SwiftUI

extension Path {
    /// Дуга SVG (равные радиусы, без поворота оси) кубическими сегментами. Конвертит
    /// endpoint-параметризацию в центр и сэмплит по ≤90 градусов — так исключена
    /// путаница флага clockwise у `Path.addArc` в y-вниз системе. Область — модуль: знаки лежат
    /// каждый в своём файле, а рисуют этой дугой все.
    mutating func addSVGArc(
        from p0: CGPoint, to p1: CGPoint,
        radius: CGFloat, largeArc: Bool, sweep: Bool
    ) {
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let chord = (dx * dx + dy * dy).squareRoot()
        guard chord > 0 else { return }
        var arcRadius = max(radius, chord / 2)  // clamp: радиус не меньше полухорды
        let halfChord = chord / 2
        let centerOffset = (arcRadius * arcRadius - halfChord * halfChord).squareRoot()
        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let unitX = dx / chord
        let unitY = dy / chord  // единичный вдоль хорды
        let perpX = -unitY
        let perpY = unitX  // перпендикуляр
        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let center = CGPoint(x: mid.x + sign * centerOffset * perpX, y: mid.y + sign * centerOffset * perpY)
        arcRadius = ((p0.x - center.x) * (p0.x - center.x) + (p0.y - center.y) * (p0.y - center.y))
            .squareRoot()

        let startAngle = atan2(p0.y - center.y, p0.x - center.x)
        let endAngle = atan2(p1.y - center.y, p1.x - center.x)
        var delta = endAngle - startAngle
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }

        let steps = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let seg = delta / CGFloat(steps)
        let handle = (4.0 / 3.0) * tan(seg / 4)  // длина ручки кубика
        var ang = startAngle
        for _ in 0..<steps {
            let nextAng = ang + seg
            let arcStart = CGPoint(x: center.x + arcRadius * cos(ang), y: center.y + arcRadius * sin(ang))
            let arcEnd = CGPoint(
                x: center.x + arcRadius * cos(nextAng), y: center.y + arcRadius * sin(nextAng))
            let control1 = CGPoint(
                x: arcStart.x - handle * arcRadius * sin(ang), y: arcStart.y + handle * arcRadius * cos(ang))
            let control2 = CGPoint(
                x: arcEnd.x + handle * arcRadius * sin(nextAng),
                y: arcEnd.y - handle * arcRadius * cos(nextAng))
            addCurve(to: arcEnd, control1: control1, control2: control2)
            ang = nextAng
        }
    }
}
