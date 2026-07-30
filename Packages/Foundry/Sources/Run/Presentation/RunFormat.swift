import Core
import SwiftUI

/// Форматирование метрик результата. Чистые функции — тестируются по граничным
/// значениям (переход на минуты ровно на 60 с).
enum RunFormat {
    /// Длительность рана: до минуты — десятые доли секунды, дальше — «м мин сс с».
    static func duration(milliseconds: Int) -> String {
        let seconds = Double(milliseconds) / 1000
        return seconds < 60
            ? String(format: "%.1f с", seconds)
            : String(format: "%d мин %02d с", Int(seconds) / 60, Int(seconds) % 60)
    }

    /// Стоимость рана в долларах — четыре знака после точки.
    static func cost(usd: Double) -> String {
        String(format: "$%.4f", usd)
    }

    /// Число ходов диалога: «N ходов». Форма родительного падежа не склоняется
    /// по числу намеренно (как в принятом макете), чтобы метрика не «прыгала».
    static func turns(_ count: Int) -> String {
        "\(count) ходов"
    }
}
