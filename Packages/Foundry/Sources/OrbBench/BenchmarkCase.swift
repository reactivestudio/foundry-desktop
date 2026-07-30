import Core

/// Один прогон замера: подпись в отчёте, пресет роя и кегль, на котором орб реально живёт
/// (тулбар, иконка, hero) — числа на разных кеглях несравнимы, потому кегль часть случая.
struct BenchmarkCase {
    let label: String
    let preset: OrbSwarmConfig.Preset
    let size: Float
}
