import MetalKit

/// Хелперы против train-wreck-цепочек по AppKit (закон Деметры): каждый прячет один обход
/// `?.…?.…` вместе с его дефолтом за именем концепта — вызывающий код спрашивает «что», а не
/// «как дойти».
extension MTKView {
    /// Масштаб backing-слоя окна (DPR). До привязки к окну — разумный дефолт
    /// Retina (2.0): раскладка роя пересчитается на первом реальном кадре.
    public var currentBackingScale: CGFloat {
        window?.backingScaleFactor ?? 2.0
    }

    /// Максимальная частота обновления экрана, на котором показано окно.
    /// Без окна/экрана — 60 Гц.
    public var displayRefreshHz: Int {
        window?.screen?.maximumFramesPerSecond ?? 60
    }
}
