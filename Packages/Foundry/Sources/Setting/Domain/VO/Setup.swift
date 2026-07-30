import Core

/**
 Состояние первичной настройки приложения — VO агрегата `Preference`: пройден ли мастер
 первого запуска. Раньше этот флаг жил в `@AppStorage("didFinishOnboarding")` прямо во вью,
 то есть durable-настройка приложения хранилась мимо агрегата настроек; теперь он здесь, и
 мастер — обычный вид BC `Setting`, а не владелец собственного состояния.

 Отдельная группа, а не поле в `General`: это не пользовательское предпочтение, а факт
 жизненного цикла приложения. Здесь же со временем появится версия пройденного мастера —
 чтобы показать его снова, когда в нём прибавится шагов.
 */
public struct Setup: ValueObject {
    /// Пройден ли мастер первого запуска (дошли до конца или вышли досрочно).
    public let isFinished: Bool

    private init(isFinished: Bool) {
        self.isFinished = isFinished
    }

    public static func of(isFinished: Bool = false) -> Setup {
        Setup(isFinished: isFinished)
    }

    /// Отметить мастер пройденным — новый VO. Идемпотентно: повторный вызов ничего не меняет.
    public func finish() -> Setup {
        Setup(isFinished: true)
    }
}
