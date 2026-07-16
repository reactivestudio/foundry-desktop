import Testing
@testable import FoundryFeatures

// Раскладка роя обязана совпадать с прототипом design/loader-logo.html число в
// число. Прототип — источник истины; разойтись они могут молча, поэтому числа
// прибиты тестом.
@Suite("Раскладка роя")
struct OrbSwarmConfigTests {

    @Test("Зерно лоадера = 1.376% — из него считается всё остальное")
    func grainLoader() {
        #expect(abs(OrbSwarmConfig.grainLoader - 0.013757) < 0.000001)
    }

    @Test("Утверждённый рой: 6000 частиц при зерне лоадера")
    func coverageMatchesApprovedSwarm() {
        let n = OrbSwarmConfig.coverage / (OrbSwarmConfig.grainLoader * OrbSwarmConfig.grainLoader)
        #expect(abs(n - 6000) < 1)
    }

    @Test("Пресеты дают числа прототипа: fine 44 701, standard 11 175")
    func presetCounts() {
        #expect(OrbSwarmConfig(preset: .fine, size: 512, scale: 1).count == 44701)
        #expect(OrbSwarmConfig(preset: .standard, size: 512, scale: 1).count == 11175)
    }

    @Test("Число частиц от размера НЕ зависит: оно следствие зерна")
    func countIndependentOfSize() {
        let small = OrbSwarmConfig(preset: .standard, size: 64, scale: 2)
        let large = OrbSwarmConfig(preset: .standard, size: 512, scale: 2)
        #expect(small.count == large.count)
    }

    @Test("Точка 2.6 pt при 512, standard — то самое зерно, что выбрали глазом")
    func pointSizeOnScreenAt512() {
        let cfg = OrbSwarmConfig(preset: .standard, size: 512, scale: 2)
        #expect(abs(cfg.pointSizeOnScreen - 2.6) < 0.01)
    }

    // Зерно безразмерно, поэтому Retina не должна менять НИ крупность на глаз,
    // НИ число частиц. Ровно это и сломалось в прототипе: точка задавалась в
    // физических пикселях и на Retina выходила вдвое мельче подписанной.
    @Test("DPR не меняет ни зерно, ни крупность на глаз")
    func scaleDoesNotChangeGrain() {
        let at1 = OrbSwarmConfig(preset: .standard, size: 512, scale: 1)
        let at2 = OrbSwarmConfig(preset: .standard, size: 512, scale: 2)
        #expect(at1.count == at2.count)
        #expect(abs(at1.pointSizeOnScreen - at2.pointSizeOnScreen) < 0.01)
    }

    @Test("Сведение включается там, где точка иначе мельче порога")
    func supersampleKicksIn() {
        // При 512 точка и так крупная — сводить нечего.
        #expect(OrbSwarmConfig(preset: .standard, size: 512, scale: 2).supersample == 1)
        // При 64 точка ушла бы под порог — сведение обязано включиться.
        #expect(OrbSwarmConfig(preset: .standard, size: 64, scale: 2).supersample > 1)
    }

    // Два ограничения, которые легко перепутать — и я их перепутал.
    // «Точка мельче порога» держит от МЕЛЬТЕШЕНИЯ на движении (время).
    // «Частиц больше, чем пикселей» держит ЗЕРНО (пространство). Проверка
    // только первого пропускала fine@64: точку он проходит, а зерна не даёт.
    @Test("Рой вырождается в пятно там, где частиц больше, чем пикселей")
    func unreadableWhenOversubscribed() {
        // Орб в тулбаре 22 pt: 5.77 частиц на пиксель — пятно, а не рой.
        let toolbar = OrbSwarmConfig(preset: .standard, size: 22, scale: 2)
        #expect(toolbar.unreadable)
        #expect(toolbar.particlesPerPixel > 5)

        // fine при 64 порог точки ПРОХОДИТ, но зерна не даёт: 2.73 частиц/px.
        let fineSmall = OrbSwarmConfig(preset: .fine, size: 64, scale: 2)
        #expect(!fineSmall.flickers, "точку он проходит — ловушка была именно тут")
        #expect(fineSmall.unreadable, "а зерна не даёт")
    }

    @Test("На своих размерах оба пресета читаются и не мельтешат")
    func presetsWorkAtTheirSizes() {
        for size in [Float(64), 128, 256, 512] {
            let cfg = OrbSwarmConfig(preset: .standard, size: size, scale: 2)
            #expect(!cfg.unreadable, "standard @ \(size) должен читаться зерном")
            #expect(!cfg.flickers, "standard @ \(size) не должен мельтешить")
        }
        for size in [Float(128), 256, 512] {
            let cfg = OrbSwarmConfig(preset: .fine, size: size, scale: 2)
            #expect(!cfg.unreadable, "fine @ \(size) должен читаться зерном")
            #expect(!cfg.flickers, "fine @ \(size) не должен мельтешить")
        }
    }

    // У fine вчетверо больше частиц, значит его порог ровно вдвое дальше:
    // частиц/px = N/выход², а выход растёт линейно.
    @Test("Порог fine ровно вдвое дальше порога standard")
    func fineFloorIsTwiceStandard() {
        let s = OrbSwarmConfig.minimumReadableSize(preset: .standard, scale: 2)
        let f = OrbSwarmConfig.minimumReadableSize(preset: .fine, scale: 2)
        #expect(abs(f / s - 2) < 0.01)
        // standard ≈ 53 pt, fine ≈ 106 pt — отсюда и «годен от 64 / от 128».
        #expect(abs(s - 52.9) < 1)
        #expect(abs(f - 105.7) < 1)
    }
}
