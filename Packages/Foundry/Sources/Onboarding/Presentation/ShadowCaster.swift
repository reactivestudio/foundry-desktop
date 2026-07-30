import SwiftUI

/// Один блок, отбрасывающий парящую тень: его рамка (anchor в координатах слоя)
/// и радиус угла. Собираются через preference и рисуются единым слоем.
struct ShadowCaster {
    let anchor: Anchor<CGRect>
    let radius: CGFloat
}
