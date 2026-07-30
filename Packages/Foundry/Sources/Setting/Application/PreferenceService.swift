import Core
import SparkIoC

/**
 Прикладная служба настроек приложения (слой Application) — ГРАНИЦА СОГЛАСОВАННОСТИ
 агрегата `Preference`. Presentation не грузит-меняет-сохраняет сам: он выражает интент
 («сменить тему», «переключить чёлку»), а служба выполняет переход атомарно поверх порта
 репозитория — читает актуальный агрегат, зовёт его команду, сохраняет целиком. Бизнес-правил
 здесь нет вовсе: они в агрегате и его VO, служба лишь оркеструет.

 Здесь же живёт правило «нет снимка — доменный дефолт»: порт отдаёт `nil`, а дефолтный
 агрегат подставляет use-case (`current()`), поэтому ни хранилище, ни вью не знают, что
 настройки могли ни разу не сохраняться.

 Побочные эффекты в ОС (автозапуск через `SMAppService` и прочее) будут зваться отсюда же,
 явным портом после `save`, — доменных событий у `Preference` намеренно нет, пока у изменения
 не появится второй независимый потребитель.

 Не `@MainActor`: состояния, привязанного к главному актору, у службы нет — она ходит в порт
 хранилища. `@ApplicationService` — стереотип бина слоя Application; операций много (по одной
 на интент агрегата), потому не `@UseCase`. Порта у службы нет, её резолвят по конкретному типу.
 */
@ApplicationService
public final class PreferenceService {
    /**
     У `PreferenceRepository` есть связанные типы (наследует `Repository`), поэтому в поле
     экзистенциал пишем явно — `any`, как того и требует Swift. В ПАРАМЕТРЕ init'а он голый
     намеренно: скан-плагин Spark 0.1.0 переносит текст типа в генерат и дописывает `.self`,
     а `any PreferenceRepository.self` без скобок не компилируется. Ценой одного
     предупреждения `#ExistentialAny` (такое же плагин печатает и у себя в `BeanScan`)
     держим граф собираемым; уйдёт, когда плагин научится скобкам.
     */
    private let repository: any PreferenceRepository

    public init(repository: PreferenceRepository) {
        self.repository = repository
    }

    /// Текущие настройки: сохранённый набор, а если его нет — доменный дефолт
    /// (агрегат валиден без единого заданного поля, см. `Preference.of`).
    public func current() -> Preference {
        repository.find(id: .default) ?? Preference.of()
    }

    // MARK: - Оформление

    public func change(theme: Theme) {
        apply { preference in
            preference.change(theme: theme)
        }
    }

    public func toggleNotch() {
        apply { preference in
            preference.toggleNotch()
        }
    }

    // MARK: - Общие

    public func toggleLaunchAtLogin() {
        apply { preference in
            preference.toggleLaunchAtLogin()
        }
    }

    public func toggleTokensInKeychain() {
        apply { preference in
            preference.toggleTokensInKeychain()
        }
    }

    public func toggleMergeReview() {
        apply { preference in
            preference.toggleMergeReview()
        }
    }

    // MARK: - Доступность

    public func toggleReduceMotion() {
        apply { preference in
            preference.toggleReduceMotion()
        }
    }

    public func toggleLargerText() {
        apply { preference in
            preference.toggleLargerText()
        }
    }

    public func toggleHigherContrast() {
        apply { preference in
            preference.toggleHigherContrast()
        }
    }

    // MARK: - Уведомления

    public func enableNotification(for type: NotificationType) {
        apply { preference in
            preference.enableNotification(for: type)
        }
    }

    public func disableNotification(for type: NotificationType) {
        apply { preference in
            preference.disableNotification(for: type)
        }
    }

    // MARK: - Связка с инструментами

    /**
     Импортировать сессию рана во внешний просмотрщик — вкл/выкл. Единственный интент, что
     принимает ЗНАЧЕНИЕ, а не флип: его зовёт `Toggle` из консоли рана, а биндинг SwiftUI
     даёт именно новое значение. Домен при этом остаётся при своём языке (булев флаг меняют
     флипом), а служба делает переход идемпотентным: значение совпало — выходим, не трогая
     ни агрегат, ни хранилище (иначе повторный биндинг писал бы файл впустую).
     */
    public func setOpensSessionInViewer(enabled: Bool) {
        guard current().integration.opensSessionInViewer != enabled else {
            return
        }

        apply { preference in
            preference.toggleOpensSessionInViewer()
        }
    }

    // MARK: - Первичная настройка

    /// Отметить мастер первого запуска пройденным (дошли до конца или вышли досрочно).
    public func finishSetup() {
        apply { preference in
            preference.finishSetup()
        }
    }

    // MARK: - Профиль

    /// Переименовать пользователя. Бросает доменную ошибку, если имя не проходит
    /// инварианты профиля, — тогда в хранилище НИЧЕГО не уходит (см. `apply`).
    public func rename(firstName: String, lastName: String) throws {
        try apply { preference in
            try preference.rename(firstName: firstName, lastName: lastName)
        }
    }

    public func change(avatar: Avatar?) {
        apply { preference in
            preference.change(avatar: avatar)
        }
    }

    /**
     Шаблон перехода, общий для всех интентов: прочитать актуальный агрегат → позвать его
     команду → сохранить целиком. Это и есть граница транзакции без БД: команда, бросившая
     доменную ошибку, до `save` не доходит, и полусостояние не сохраняется (`rethrows` —
     чтобы один шаблон обслуживал и падающие интенты вроде `rename`, и обычные).
     */
    private func apply(change: (Preference) throws -> Void) rethrows {
        let preference = current()
        try change(preference)
        repository.save(entity: preference)
    }
}
