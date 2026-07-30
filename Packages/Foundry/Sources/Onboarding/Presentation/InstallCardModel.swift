import SwiftUI

/// Данные карточки.
struct InstallCardModel: Identifiable {
    let id: String
    let glyph: OBGlyph
    let vendor: String
    let name: String
    let requirement: String  // факт/требование в состоянии «не установлено»
    let installedDetail: String?  // вторая строка фактов у установленного (план и т.п.)
    let signedInLabel: String  // строка «✓ … signed in» после установки
    let showsInstall: Bool  // есть ли кнопка Install (у Claude в стенде уже стоит)
}
