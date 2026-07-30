import AppKit
import Core
import CoreGraphics
import SwiftUI

/// Истинный гиперэллипс — то, что CSS зовёт `corner-shape: squircle` = superellipse(2) =
/// показатель n=4: |x|⁴+|y|⁴=1. `RoundedRectangle(.continuous)` — лишь приближение Apple
/// (заметно круглее по бокам); здесь угол строится ровно по кривой макета. Экспонента
/// параметризации 2/n = 0.5: точка четвертинки = (cos t)^0.5, (sin t)^0.5.
struct Squircle: InsettableShape {
    var cornerRadius: CGFloat
    /// Показатель суперэллипса |x|ⁿ+|y|ⁿ=1. Канон системы — 4 (CSS `corner-shape:
    /// squircle`). Меньше — угол ближе к дуге окружности и читается круглее (n=2 —
    /// ровно окружность); больше — угол площе, ближе к прямому.
    var exponent: CGFloat = 4
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let rad = max(0, min(cornerRadius - insetAmount, min(r.width, r.height) / 2))
        guard rad > 0 else { return Path(r) }
        let x0 = r.minX
        let y0 = r.minY
        let x1 = r.maxX
        let y1 = r.maxY
        let seg = 16
        let e = 2 / exponent  // экспонента параметризации: n=4 → 0.5, n=2 → 1 (окружность)
        func se(_ i: Int) -> (CGFloat, CGFloat) {
            let t = (.pi / 2) * CGFloat(i) / CGFloat(seg)
            return (pow(cos(t), e), pow(sin(t), e))
        }
        var p = Path()
        p.move(to: CGPoint(x: x0 + rad, y: y0))
        p.addLine(to: CGPoint(x: x1 - rad, y: y0))
        for i in 0...seg {
            let (c, s) = se(i)  // верх-право
            p.addLine(to: CGPoint(x: x1 - rad + rad * s, y: y0 + rad - rad * c))
        }
        p.addLine(to: CGPoint(x: x1, y: y1 - rad))
        for i in 0...seg {
            let (c, s) = se(i)  // низ-право
            p.addLine(to: CGPoint(x: x1 - rad + rad * c, y: y1 - rad + rad * s))
        }
        p.addLine(to: CGPoint(x: x0 + rad, y: y1))
        for i in 0...seg {
            let (c, s) = se(i)  // низ-лево
            p.addLine(to: CGPoint(x: x0 + rad - rad * s, y: y1 - rad + rad * c))
        }
        p.addLine(to: CGPoint(x: x0, y: y0 + rad))
        for i in 0...seg {
            let (c, s) = se(i)  // верх-лево
            p.addLine(to: CGPoint(x: x0 + rad - rad * c, y: y0 + rad - rad * s))
        }
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Squircle {
        var s = self
        s.insetAmount += amount
        return s
    }
}
