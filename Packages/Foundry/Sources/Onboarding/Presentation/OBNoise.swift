import CoreGraphics
import SwiftUI

/// Мелкодисперсный шум фона. Плоская заливка идеально однородна и оттого «мёртвая»;
/// лёгкий шум микрооттенков (как дизеринг в прототипе) оживляет фон — глазу почти
/// не виден, проступает лишь при увеличении. Тайл случайных значений вокруг
/// нейтрального серого 128, блендится `.overlay` (серый = без сдвига, отклонения
/// чуть светлят/темнят каждый пиксель; на тёмном фоне эффект пропорционально мал).
enum OBNoise {
    static let tile = 256  // сторона тайла, px (высокочастотный шум — швов не видно)
    static let amplitude = 27  // размах отклонения от серого 128 (± amplitude), 0…127
    static let opacity: Double = 0.7  // сила проявления (масштабирует отклонения)

    static let image: CGImage = make()

    private static func make() -> CGImage {
        let side = tile
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15  // детерминированный xorshift — стабилен между запусками
        func nextRandom() -> Int {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Int(truncatingIfNeeded: seed) & 0xFF
        }
        for index in 0..<(side * side) {
            let value = 128 + (nextRandom() % (2 * amplitude + 1)) - amplitude
            let gray = UInt8(clamping: value)
            pixels[index * 4 + 0] = gray
            pixels[index * 4 + 1] = gray
            pixels[index * 4 + 2] = gray
            pixels[index * 4 + 3] = 255
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Контекст И снимок — внутри withUnsafeMutableBytes. Указатель из `&px`
        // действителен только на время самого вызова CGContext.init, а буфер
        // читается позже, в makeImage() — снаружи это висячий указатель (массиву
        // ничто не мешает освободиться сразу после init, он больше не нужен).
        // makeImage() копирует байты, поэтому наружу уходит самостоятельный
        // CGImage, не завязанный на время жизни массива.
        return pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return context.makeImage()!
        }
    }
}
