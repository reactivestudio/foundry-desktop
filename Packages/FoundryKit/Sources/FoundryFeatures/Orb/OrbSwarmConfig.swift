import Foundation

/// Раскладка роя под конкретный размер: зерно → число частиц, сведение, буфер.
///
/// Арифметика перенесена из `design/loader-logo.html` и должна совпадать с ним
/// число в число — прототип остаётся источником истины.
public struct OrbSwarmConfig: Equatable, Sendable {

    /// Тело орба занимает 0.21 кадра на единицу зума. Через него задаётся
    /// ЗЕРНО — размер частицы как доля тела.
    static let orb: Float = 0.21
    /// Логотип кадрируется теснее лоадера: орб на весь квадрат.
    static let zoom: Float = 2.4
    /// Дальняя частица вдвое мельче ближней — как в лоадере.
    static let taper: Float = 0.5

    /// Зерно утверждённого лоадера: точка 2.6 px в кадре 900 против тела кадра.
    static let grainLoader: Float = (2.6 * 2.4 / 900) / (orb * 2.4)   // 1.376%

    /// Заполненность утверждённого роя = N × зерно². Держим её постоянной,
    /// поэтому N = coverage / зерно². Без пересчёта «мельче зерно» означало бы
    /// «реже рой», а не «тоньше помол».
    static let coverage: Float = 6000 * grainLoader * grainLoader

    /// Ниже этого размера точка занимает считанные пиксели и на движении
    /// перепрыгивает всю свою ширину — рой начинает мельтешить. Ограничение
    /// временнОе: про движение, не про картинку.
    static let minPointSize: Float = 1.8
    /// Потолок сверхвыборки: дальше растёт цена, а не качество.
    static let maxSupersample: Int = 8

    /// Утверждённые эталоны зерна. Оба одобрены, отличаются только помолом.
    public enum Preset: String, CaseIterable, Sendable {
        /// Тонкий помол: зерно вдвое мельче лоадерного, рой читается пылью.
        /// Цена — 44 701 частица, и ниже 128 такое зерно в пиксель не влезает.
        case fine
        /// Зерно ближе к утверждённому лоадеру, вчетверо дешевле. Годен от 64.
        case standard

        var grain: Float {
            switch self {
            case .fine:     return 0.00504
            case .standard: return 0.01008
            }
        }

        /// Частота, ниже которой рой заметно шагает.
        ///
        /// Замер: за кадр частица сдвигается на 1.4 своего диаметра при 30 fps,
        /// то есть уходит дальше собственной ширины и след рвётся. Порог — там,
        /// где сдвиг равен диаметру: 41 fps. Число от размера НЕ зависит, и
        /// сдвиг, и диаметр растут линейно, их отношение постоянно.
        ///
        /// У fine зерно вдвое мельче при том же сдвиге, поэтому порог вдвое выше.
        var minimumFramesPerSecond: Int {
            switch self {
            case .fine:     return 82
            case .standard: return 41
            }
        }
    }

    public let grain: Float
    /// Логический размер в точках (SwiftUI pt), без учёта Retina.
    public let size: Float
    /// Пикселей на точку — 2.0 на Retina.
    public let scale: Float
    /// Сторона выходной текстуры в пикселях.
    public let output: Int
    /// Во сколько раз буфер крупнее выхода.
    public let supersample: Int
    /// Сторона буфера частиц в пикселях.
    public let buffer: Int
    /// Размер точки в пикселях буфера.
    public let pointSize: Float
    public let count: Int
    /// Сведение упёрлось в потолок, а точка так и не дотянула до порога: рой
    /// будет мельтешить на движении.
    ///
    /// Молчаливый кламп тут недопустим — он и был причиной мельтешения роя на
    /// малых размерах в прежних попытках. Драйвер меньше 1 px всё равно не
    /// рисует, то есть мелкое зерно не «мельчает», а просто врёт.
    public let flickers: Bool

    public init(preset: Preset = .standard, size: Float, scale: Float) {
        self.init(grain: preset.grain, size: size, scale: scale)
    }

    public init(grain: Float, size: Float, scale: Float) {
        self.grain = grain
        self.size = size
        self.scale = scale

        let out = max(1, Int((size * scale).rounded()))
        self.output = out

        var ss = 1
        while ss < Self.maxSupersample,
              grain * Self.orb * Self.zoom * Float(out) * Float(ss) < Self.minPointSize {
            ss *= 2
        }
        self.supersample = ss
        self.buffer = out * ss

        let pt = grain * Self.orb * Self.zoom * Float(buffer)
        self.pointSize = pt
        self.count = Int((Self.coverage / (grain * grain)).rounded())
        self.flickers = pt < Self.minPointSize
    }

    /// Размер точки в точках экрана — то, что видит глаз.
    public var pointSizeOnScreen: Float { pointSize / (scale * Float(supersample)) }

    /// Частиц на один выходной пиксель.
    public var particlesPerPixel: Float { Float(count) / Float(output * output) }

    /// Рой выродился в пятно: частиц больше, чем пикселей, чтобы их показать.
    ///
    /// Это не порог вкуса, а принцип Дирихле: при `particlesPerPixel > 1`
    /// различить частицы нельзя в принципе — каждый пиксель показывает среднее
    /// нескольких, и «рой» читается сплошной кляксой. Замер это подтверждает:
    /// на 0.68 зерно видно, на 2.73 его нет.
    ///
    /// Ограничение пространственное и от `flickers` независимое. Их легко
    /// перепутать: `fine` при 64 порог точки проходит, а зерна не даёт —
    /// частиц на пиксель 2.73.
    public var unreadable: Bool { particlesPerPixel > 1 }

    /// Наименьший размер, на котором зерно пресета ещё читается: там, где
    /// частиц ровно по пикселю. Ниже — пятно.
    public static func minimumReadableSize(preset: Preset, scale: Float) -> Float {
        let count = Self.coverage / (preset.grain * preset.grain)
        return count.squareRoot() / scale
    }

    /// Экран не даёт пресету его порога частоты — рой будет заметно шагать.
    ///
    /// Третье ограничение, независимое от `flickers` и `unreadable`: те про
    /// размер, это про экран. `fine` требует 82 fps, поэтому на обычных 60 Гц
    /// он недостижим в принципе — тонкий помол годен в движении только на
    /// ProMotion. Молчать об этом нельзя: кламп до 60 не «почти выполняет»
    /// порог, а рвёт след частицы, ради которого зерно и мельчили.
    public static func steps(preset: Preset, displayHz: Int) -> Bool {
        displayHz < preset.minimumFramesPerSecond
    }

    /// Наименьшая частота, которую экран РЕАЛЬНО умеет и которая не ниже порога
    /// пресета.
    ///
    /// Просить ровно порог нельзя: система выдаёт только делители частоты
    /// экрана, и запрос 41 на 60 Гц округлится вниз, до 30 — то есть под порог,
    /// ради обхода которого всё и считалось. Поэтому берём ступень сверху.
    ///
    /// На ProMotion это ещё и экономит: standard получит 60 из 120 — порог
    /// выполнен, а кадров вдвое меньше.
    public static func achievableFrameRate(preset: Preset, displayHz: Int) -> Int {
        let divisor = displayHz / preset.minimumFramesPerSecond
        guard divisor >= 1 else { return displayHz }   // порог недостижим — выжимаем максимум
        return displayHz / divisor
    }

    public var summary: String {
        var out = "\(Int(size)) · зерно \(String(format: "%.3f", grain * 100))% · \(count) частиц"
            + " · точка \(String(format: "%.2f", pointSizeOnScreen)) pt · сведение ×\(supersample)"
            + " · буфер \(buffer)"
            + " · \(String(format: "%.2f", particlesPerPixel)) частиц/px"
        if unreadable {
            out += "\n⚠ частиц больше, чем пикселей (\(String(format: "%.2f", particlesPerPixel))/px):"
                + " рой вырождается в пятно"
        }
        if flickers {
            out += "\n⚠ точка \(String(format: "%.2f", pointSize)) px в буфере при пороге"
                + " \(Self.minPointSize): рой будет мельтешить на движении"
        }
        return out
    }
}
