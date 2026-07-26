import AppKit
import MetalKit

// Хелперы против train-wreck-цепочек по AppKit (закон Деметры). Каждый прячет
// один обход `?.…?.…` вместе с его дефолтом за именем концепта — вызывающий код
// спрашивает «что», а не «как дойти».

extension MTKView {
    /// Масштаб backing-слоя окна (DPR). До привязки к окну — разумный дефолт
    /// Retina (2.0): раскладка роя пересчитается на первом реальном кадре.
    var currentBackingScale: CGFloat {
        window?.backingScaleFactor ?? 2.0
    }

    /// Максимальная частота обновления экрана, на котором показано окно.
    /// Без окна/экрана — 60 Гц.
    var displayRefreshHz: Int {
        window?.screen?.maximumFramesPerSecond ?? 60
    }
}

extension NSWindow {
    /// Приватный frame-view окна — надвид `contentView`, на котором живут
    /// скругление углов и подвиды титлбара. AppKit не даёт его именем, только
    /// через `contentView.superview`; это имя избавляет от голой цепочки.
    var frameView: NSView? {
        contentView?.superview
    }
}
