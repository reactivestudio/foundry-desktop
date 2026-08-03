import CoreGraphics

/**
 Кадр главного окна — числами доски, а не корня композиции.

 Про окно приложения знает корень композиции (`WindowConfigurator`), но про
 то, СКОЛЬКО окну нужно, знает только экран: минимум диктуют неделимые части
 (рейл со словами под знаками, строка пульта, дорожка доски), а предпочтение —
 кадр эталона, где восемь стадий, шов и корзина видны разом, без прокрутки.
 Поэтому геометрия остаётся здесь, а наружу выходят две величины.
 */
public enum BoardWindowFrame {
    /// Кадр эталона: вся доска пайплайна из восьми стадий видна целиком.
    public static var preferred: CGSize {
        CGSize(width: BoardMetrics.etalonWindowWidth, height: BoardMetrics.etalonWindowHeight)
    }

    /// Меньше — экран перестаёт быть собой: доска короче трёх стадий уже
    /// не доска, а рейл с восемью разделами не делится вовсе.
    public static var minimum: CGSize {
        CGSize(width: BoardMetrics.minimumWindowWidth, height: BoardMetrics.minimumWindowHeight)
    }

    /// Высота собственного титлбара экрана. Системный вдвое ниже, и потому
    /// светофор, оставленный системе, висит под потолком вместо середины.
    public static var titlebarHeight: CGFloat { BoardMetrics.titlebarHeight }

    /// Левое поле окна: на нём стоит и кромка рейла, и светофор. Кнопки
    /// системные — их не рисуют заново, их двигают на этот флаг.
    public static var titlebarLeading: CGFloat { BoardMetrics.windowPadding }
}
