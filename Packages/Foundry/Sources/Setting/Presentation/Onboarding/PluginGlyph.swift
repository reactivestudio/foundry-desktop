import SwiftUI

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
