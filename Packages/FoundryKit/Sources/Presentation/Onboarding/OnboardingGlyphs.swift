import SwiftUI

/// Вендорские знаки и пиктограммы частей — перерисованы из SVG макета в Path,
/// потому что macOS не декодирует SVG нативно. Все viewBox 64 или 24, знак
/// масштабируется под запрошенный кегль.

// MARK: - SVG-дуга → кубики

extension Path {
    /// Дуга SVG (равные радиусы, без поворота оси) кубическими сегментами. Конвертит
    /// endpoint-параметризацию в центр и сэмплит по ≤90 градусов — так исключена
    /// путаница флага clockwise у `Path.addArc` в y-вниз системе.
    fileprivate mutating func addSVGArc(
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

// MARK: - Знаки агентов (viewBox 64)

/// Астериск Claude — шесть лучей, монолиния белым (вендор-знаки однотонны).
struct ClaudeGlyph: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 64
            let lines: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (55, 32, 9, 32), (51.9, 20.5, 12.1, 43.5), (43.5, 12.1, 20.5, 51.9),
                (32, 9, 32, 55), (20.5, 12.1, 43.5, 51.9), (12.1, 20.5, 51.9, 43.5),
            ]
            var p = Path()
            for (x1, y1, x2, y2) in lines {
                p.move(to: CGPoint(x: x1 * s, y: y1 * s))
                p.addLine(to: CGPoint(x: x2 * s, y: y2 * s))
            }
            ctx.stroke(
                p, with: .color(.white.opacity(0.9)),
                style: StrokeStyle(lineWidth: 5.4 * s, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Три эллипса OpenAI, монолиния белым.
struct OpenAIGlyph: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 64
            for deg in [0.0, 60.0, 120.0] {
                var e = Path(
                    ellipseIn: CGRect(
                        x: -10.5 * s, y: -24 * s,
                        width: 21 * s, height: 48 * s))
                e = e.applying(CGAffineTransform(rotationAngle: deg * .pi / 180))
                e = e.applying(CGAffineTransform(translationX: 32 * s, y: 32 * s))
                ctx.stroke(e, with: .color(.white), style: StrokeStyle(lineWidth: 4.2 * s))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Четырёхлучевая звезда Gemini, заливка белым (вендор-знаки однотонны).
struct GeminiGlyph: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 64
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var p = Path()
            p.move(to: pt(32, 5))
            p.addCurve(to: pt(59, 32), control1: pt(33.6, 19), control2: pt(45, 30.4))
            p.addCurve(to: pt(32, 59), control1: pt(45, 33.6), control2: pt(33.6, 45))
            p.addCurve(to: pt(5, 32), control1: pt(30.4, 45), control2: pt(19, 33.6))
            p.addCurve(to: pt(32, 5), control1: pt(19, 30.4), control2: pt(30.4, 19))
            p.closeSubpath()
            ctx.fill(p, with: .color(.white.opacity(0.9)))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Пиктограммы частей Foundry (viewBox 24, монолиния, без подложки)

/// Пазл — знак плагина, часть, встающая в вырез Claude Code.
struct PluginGlyph: View {
    var size: CGFloat = 24
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var p = Path()
            p.move(to: pt(8, 6))
            p.addLine(to: pt(9.4, 6))
            p.addSVGArc(from: pt(9.4, 6), to: pt(14.6, 6), radius: 2.6 * s, largeArc: false, sweep: true)
            p.addLine(to: pt(16, 6))
            p.addSVGArc(from: pt(16, 6), to: pt(18, 8), radius: 2 * s, largeArc: false, sweep: true)
            p.addLine(to: pt(18, 9.4))
            p.addSVGArc(from: pt(18, 9.4), to: pt(18, 14.6), radius: 2.6 * s, largeArc: false, sweep: true)
            p.addLine(to: pt(18, 16))
            p.addSVGArc(from: pt(18, 16), to: pt(16, 18), radius: 2 * s, largeArc: false, sweep: true)
            p.addLine(to: pt(8, 18))
            p.addSVGArc(from: pt(8, 18), to: pt(6, 16), radius: 2 * s, largeArc: false, sweep: true)
            p.addLine(to: pt(6, 8))
            p.addSVGArc(from: pt(6, 8), to: pt(8, 6), radius: 2 * s, largeArc: false, sweep: true)
            p.closeSubpath()
            ctx.stroke(
                p, with: .color(.white.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.25 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Приглашение `>_` — знак foundry-cli.
struct CLIGlyph: View {
    var size: CGFloat = 24
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var p = Path()
            p.move(to: pt(5.2, 7.2))
            p.addLine(to: pt(10.8, 12))
            p.addLine(to: pt(5.2, 16.8))
            p.move(to: pt(13.2, 16.8))
            p.addLine(to: pt(18.8, 16.8))
            ctx.stroke(
                p, with: .color(.white.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.25 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}
