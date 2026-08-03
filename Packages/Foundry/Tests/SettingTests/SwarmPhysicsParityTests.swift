import Testing

@testable import Core
@testable import Setting

/// Тест-паритет двух роёв: рой мастера настройки (презентация BC `Setting`) держит
/// СОБСТВЕННЫЕ копии чисел прототипа — он заморожен пиксельно, а орб-лоадер
/// (`Core`) ещё тюнится, поэтому связывать константы напрямую нельзя. Но сегодня
/// физика у них общая и разъехаться может молча. Этот тест — единый источник истины
/// вместо связки: чуть двинется любая сторона — упадёт CI. Смотрит во внутренности
/// обеих сторон (`@testable` Core+Setting).
@Suite("Паритет физики роёв")
struct SwarmPhysicsParityTests {

    @Test("Физика роя мастера настройки совпадает с OrbSwarmConfig (иначе рои разъедутся молча)")
    func setupSwarmMatchesOrbPhysics() {
        #expect(SetupSwarmView.orbBodyFraction == OrbSwarmConfig.orbBodyFraction)
        #expect(SetupSwarmView.zoom == OrbSwarmConfig.zoom)
        #expect(SetupSwarmView.taper == OrbSwarmConfig.taper)
        #expect(SetupSwarmView.loaderGrain == OrbSwarmConfig.loaderGrain)
        #expect(SetupSwarmView.coverage == OrbSwarmConfig.coverage)
        #expect(SetupSwarmView.minPointSize == OrbSwarmConfig.minPointSize)
        #expect(SetupSwarmView.maxSupersample == OrbSwarmConfig.maxSupersample)
        // Зерно мастера настройки — это зерно пресета fine; число частиц из него же.
        #expect(SetupSwarmView.grain == OrbSwarmConfig.Preset.fine.grain)
        #expect(
            SetupSwarmView.particleCount
                == OrbSwarmConfig(preset: .fine, size: 512, scale: 1).particleCount)
    }
}
