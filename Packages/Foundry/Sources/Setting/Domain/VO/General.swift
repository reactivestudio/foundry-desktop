import Core

/**
 Общие настройки приложения — VO агрегата `Preference`. Иммутабелен; `of` задаёт
 дефолты. Все поля булевы — меняются флипом `toggle…()` (возвращает новый VO).
 */
public struct General: ValueObject {
    public let launchAtLogin: Bool
    public let tokensInKeychain: Bool
    public let mergeReview: Bool

    private init(launchAtLogin: Bool, tokensInKeychain: Bool, mergeReview: Bool) {
        self.launchAtLogin = launchAtLogin
        self.tokensInKeychain = tokensInKeychain
        self.mergeReview = mergeReview
    }

    public static func of(
        launchAtLogin: Bool = false,
        tokensInKeychain: Bool = true,
        mergeReview: Bool = true
    ) -> General {
        General(launchAtLogin: launchAtLogin, tokensInKeychain: tokensInKeychain, mergeReview: mergeReview)
    }

    /// Переключить автозапуск при входе — новый VO с инвертированным флагом.
    public func toggleLaunchAtLogin() -> General {
        with(launchAtLogin: !launchAtLogin)
    }

    /// Переключить хранение токенов в Keychain — новый VO с инвертированным флагом.
    public func toggleTokensInKeychain() -> General {
        with(tokensInKeychain: !tokensInKeychain)
    }

    /// Переключить авто-ревью слияний — новый VO с инвертированным флагом.
    public func toggleMergeReview() -> General {
        with(mergeReview: !mergeReview)
    }

    /**
     Копия с точечной заменой полей (`nil` — оставить как есть). Приватная: повтор
     перечисления всех полей живёт в одном месте, наружу — только намерения `toggle…`.
     */
    private func with(
        launchAtLogin: Bool? = nil,
        tokensInKeychain: Bool? = nil,
        mergeReview: Bool? = nil
    ) -> General {
        General(
            launchAtLogin: launchAtLogin ?? self.launchAtLogin,
            tokensInKeychain: tokensInKeychain ?? self.tokensInKeychain,
            mergeReview: mergeReview ?? self.mergeReview
        )
    }
}
