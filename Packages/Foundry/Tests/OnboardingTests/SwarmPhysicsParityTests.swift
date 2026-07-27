import Testing

@testable import Core
@testable import Onboarding

/// Межконтекстный тест-паритет: онбординг-рой (`Onboarding`) держит СОБСТВЕННЫЕ
/// копии чисел прототипа — он заморожен пиксельно, а орб-лоадер (`Core`) ещё
/// тюнится, поэтому связывать константы напрямую нельзя. Но сегодня физика у них
/// общая и разъехаться может молча. Этот тест — единый источник истины вместо
/// связки: чуть двинется любая сторона — упадёт CI. Живёт в `OnboardingTests`,
/// потому что смотрит во внутренности обоих контекстов (`@testable` Core+Onboarding).
@Suite("Паритет физики роёв")
struct SwarmPhysicsParityTests {

    @Test("Физика онбординг-роя совпадает с OrbSwarmConfig (иначе рои разъедутся молча)")
    func onboardingSwarmMatchesOrbPhysics() {
        #expect(OnboardingSwarmView.orbBodyFraction == OrbSwarmConfig.orbBodyFraction)
        #expect(OnboardingSwarmView.zoom == OrbSwarmConfig.zoom)
        #expect(OnboardingSwarmView.taper == OrbSwarmConfig.taper)
        #expect(OnboardingSwarmView.loaderGrain == OrbSwarmConfig.loaderGrain)
        #expect(OnboardingSwarmView.coverage == OrbSwarmConfig.coverage)
        #expect(OnboardingSwarmView.minPointSize == OrbSwarmConfig.minPointSize)
        #expect(OnboardingSwarmView.maxSupersample == OrbSwarmConfig.maxSupersample)
        // Зерно онбординга — это зерно пресета fine; число частиц из него же.
        #expect(OnboardingSwarmView.grain == OrbSwarmConfig.Preset.fine.grain)
        #expect(
            OnboardingSwarmView.particleCount
                == OrbSwarmConfig(preset: .fine, size: 512, scale: 1).particleCount)
    }
}
