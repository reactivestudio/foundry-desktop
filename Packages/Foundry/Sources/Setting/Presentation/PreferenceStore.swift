import Observation
import SparkIoC

/**
 Стор настроек — тонкий контроллер презентационного слоя BC `Setting`, ОДИН на оба вида:
 мастер первого запуска (`Presentation/Onboarding`) и будущее окно настроек. Держит снимок
 агрегата, отдаёт вью его группы-VO только на чтение и принимает интенты, делегируя их
 сценарию `PreferenceService`.

 Наружу торчат ИММУТАБЕЛЬНЫЕ группы (`Appearance`, `General`, …), а сам агрегат — приватный:
 иначе вью получило бы мутабельный корень и могло бы менять настройки мимо сценария, то есть
 мимо сохранения. Менять — только интентом стора.

 После каждого интента снимок перечитывается целиком (`reload`): агрегат — ссылочный тип, и
 его внутренняя мутация не разбудила бы наблюдение SwiftUI; присваивание свежего инстанса
 будит. Заодно вью видит ровно то, что легло в хранилище, — а не то, что мы надеялись туда
 положить.

 `@Store` — стереотип бина слоя Presentation (наш аналог `@Controller`): контейнер собирает
 стор сам, внедряя сценарий. `@MainActor` — состояние экрана живёт на главном акторе, бин
 confined и ленив.
 */
@MainActor
@Observable
@Store
public final class PreferenceStore {
    /// Снимок агрегата. Приватен намеренно (см. док типа): наружу — только группы-VO.
    private var preference: Preference

    // Зависимость, не состояние: из наблюдения исключена (практики 03).
    @ObservationIgnored private let service: PreferenceService

    public init(service: PreferenceService) {
        self.service = service
        preference = service.current()
    }

    // MARK: - Чтение (иммутабельные группы агрегата)

    public var profile: Profile { preference.profile }
    public var appearance: Appearance { preference.appearance }
    public var notification: Notification { preference.notification }
    public var general: General { preference.general }
    public var accessibility: Accessibility { preference.accessibility }
    public var integration: Integration { preference.integration }
    public var agent: Agent { preference.agent }
    public var setup: Setup { preference.setup }

    // MARK: - Интенты вью

    public func change(theme: Theme) {
        service.change(theme: theme)
        reload()
    }

    public func toggleNotch() {
        service.toggleNotch()
        reload()
    }

    public func toggleLaunchAtLogin() {
        service.toggleLaunchAtLogin()
        reload()
    }

    public func toggleTokensInKeychain() {
        service.toggleTokensInKeychain()
        reload()
    }

    public func toggleMergeReview() {
        service.toggleMergeReview()
        reload()
    }

    public func toggleReduceMotion() {
        service.toggleReduceMotion()
        reload()
    }

    public func toggleLargerText() {
        service.toggleLargerText()
        reload()
    }

    public func toggleHigherContrast() {
        service.toggleHigherContrast()
        reload()
    }

    public func enableNotification(for type: NotificationType) {
        service.enableNotification(for: type)
        reload()
    }

    public func disableNotification(for type: NotificationType) {
        service.disableNotification(for: type)
        reload()
    }

    public func muteNotifications() {
        service.muteNotifications()
        reload()
    }

    public func unmuteNotifications() {
        service.unmuteNotifications()
        reload()
    }

    /**
     Единый тумблер уведомлений: молчим — включить все виды, включён хоть один — погасить
     все. Ветвление живёт ЗДЕСЬ, в презентации, а не в домене: «один переключатель на
     группу» — это форма экрана (у мастера места на пять галочек нет), домен же знает два
     ясных намерения — молчать и уведомлять. Экран с per-type галочками позовёт
     `enableNotification(for:)`/`disableNotification(for:)` и в этот метод не заглянет.
     */
    public func toggleNotifications() {
        if notification.isMuted {
            unmuteNotifications()
        } else {
            muteNotifications()
        }
    }

    public func change(agent: ToolId) {
        service.change(agent: agent)
        reload()
    }

    /// Мастер первого запуска пройден — гейт в корне композиции уступает место
    /// главному окну, и при следующем запуске мастера уже не будет.
    public func finishSetup() {
        service.finishSetup()
        reload()
    }

    // Профиля (имя, аватар) в интентах пока нет: экрана у него тоже нет, а падающий
    // `rename` требует решить, как вью показывает доменную ошибку. Появится вместе с
    // экраном профиля — и тогда с этим решением, а не наперёд.

    /// Перечитать снимок из хранилища — единственная точка обновления состояния.
    private func reload() {
        preference = service.current()
    }
}
