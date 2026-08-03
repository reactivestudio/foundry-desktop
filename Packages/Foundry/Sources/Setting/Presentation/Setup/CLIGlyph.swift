import SwiftUI

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
