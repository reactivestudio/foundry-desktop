import SwiftSyntax

extension DeclGroupSyntax {
    /// Префикс доступа для witness'а, сгенерированного в extension этого типа: witness должен быть НЕ
    /// МЕНЕЕ доступен, чем требование протокола. `open` у static/метода не бывает → `public`;
    /// `private` witness в extension не удовлетворяет требование → минимум `fileprivate`. Возвращает
    /// префикс с завершающим пробелом (или пустую строку для дефолтного доступа).
    var extensionMemberAccessPrefix: String {
        let levels: Set<String> = ["open", "public", "package", "internal", "fileprivate", "private"]
        let level = modifiers.first { levels.contains($0.name.text) }?.name.text

        return level.map { name in
            switch name {
            case "open": "public "
            case "private": "fileprivate "
            default: "\(name) "
            }
        } ?? ""
    }
}
