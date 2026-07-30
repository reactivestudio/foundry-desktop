import AppKit
import Core
import CoreGraphics
import SwiftUI

/// Микрорельеф кромок (канон 09): на bg.base поверхность отделяет СВЕТ по кромке,
/// не тёмная тень — еле заметный блик сверху (0.05) и лёгкая подрезка снизу.
struct EdgeRelief: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay(
            OB.squircle(radius).strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), .clear, .clear, Color.black.opacity(0.14)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        )
    }
}
