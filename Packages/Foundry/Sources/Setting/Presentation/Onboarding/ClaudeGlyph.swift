import SwiftUI

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
