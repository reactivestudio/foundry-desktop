import CoreGraphics
import SwiftUI

/// Фон окна установки: `OB.backdrop` с тонким шумом микрооттенков поверх (см. OBNoise).
struct WindowBackdrop: View {
    var body: some View {
        OB.backdrop.overlay(
            // scale: 2 → один тексель шума = 1 физический пиксель на retina (самое
            // мелкое зерно); при scale 1 тексель занимал 1 point = 2 px, было крупнее.
            Image(decorative: OBNoise.image, scale: 2)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(OBNoise.opacity)
        )
        .compositingGroup()  // изолировать бленд шума на паре (fon+шум), не на рой ниже
    }
}
