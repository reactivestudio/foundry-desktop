import SwiftUI

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
