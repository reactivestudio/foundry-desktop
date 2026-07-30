import AppKit

extension NSWindow {
    /// Приватный frame-view окна — надвид `contentView`, на котором живут
    /// скругление углов и подвиды титлбара. AppKit не даёт его именем, только
    /// через `contentView.superview`; это имя избавляет от голой цепочки
    /// (закон Деметры, как и в `MTKView+ScreenMetrics`).
    public var frameView: NSView? {
        contentView?.superview
    }
}
