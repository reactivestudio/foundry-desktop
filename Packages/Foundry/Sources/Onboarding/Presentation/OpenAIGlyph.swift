import SwiftUI

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
