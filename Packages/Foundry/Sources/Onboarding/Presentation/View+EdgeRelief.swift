import AppKit
import Core
import CoreGraphics
import SwiftUI

extension View {
    func edgeRelief(_ radius: CGFloat) -> some View { modifier(EdgeRelief(radius: radius)) }
    /// Курсор-рука на кликабельном. В макете (веб) у всего кликабельного
    /// `cursor: pointer`; в нативе по умолчанию курсор не меняется — вешаем
    /// системный link-указатель. Работает на КЛЮЧЕВОМ окне; на неактивном окне
    /// macOS свой курсор показывать почти не даёт — по договорённости не боремся.
    func clickCursor() -> some View { pointerStyle(.link) }
}
