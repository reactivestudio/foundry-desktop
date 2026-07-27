@testable import Setting
import Testing

@Suite("Профиль (VO)")
struct ProfileTests {

    @Test("Фабрика нормализует пробелы по краям")
    func factoryTrimsWhitespace() throws {
        let profile = try Profile.of(firstName: "  Ada  ", lastName: "\tLovelace\n")
        #expect(profile.firstName == "Ada")
        #expect(profile.lastName == "Lovelace")
    }

    @Test("Имя длиннее предела — доменная ошибка")
    func tooLongNameRejected() {
        let overLimit = String(repeating: "a", count: Profile.maxNameLength + 1)
        #expect(throws: NameTooLongError.self) {
            try Profile.of(firstName: overLimit)
        }
    }

    @Test("Ровно предел длины — валидно")
    func exactLimitAccepted() throws {
        let atLimit = String(repeating: "a", count: Profile.maxNameLength)
        let profile = try Profile.of(firstName: atLimit)
        #expect(profile.firstName.count == Profile.maxNameLength)
    }

    @Test("Полное имя не плодит лишних пробелов на пустых частях")
    func fullNameHandlesEmptyParts() throws {
        #expect(try Profile.of(firstName: "Ada", lastName: "Lovelace").fullName == "Ada Lovelace")
        #expect(try Profile.of(firstName: "Ada").fullName == "Ada")
        #expect(try Profile.of(lastName: "Lovelace").fullName == "Lovelace")
        #expect(Profile.empty.fullName == "")
    }

    @Test("Инициалы — до двух букв в верхнем регистре")
    func initialsUpToTwoUppercase() throws {
        #expect(try Profile.of(firstName: "ada", lastName: "lovelace").initials == "AL")
        #expect(try Profile.of(firstName: "ada").initials == "A")
        #expect(Profile.empty.initials == "")
    }

    @Test("Переименование сохраняет аватар и валидирует")
    func renameKeepsAvatarAndValidates() throws {
        let avatar = try Avatar.of(reference: "avatar.png")
        let profile = try Profile.of(firstName: "Ada", avatar: avatar)

        let renamed = try profile.rename(firstName: "Grace", lastName: "Hopper")
        #expect(renamed.fullName == "Grace Hopper")
        #expect(renamed.avatar == avatar)

        let overLimit = String(repeating: "a", count: Profile.maxNameLength + 1)
        #expect(throws: NameTooLongError.self) {
            try profile.rename(firstName: overLimit, lastName: "")
        }
    }

    @Test("Смена аватара ставит и снимает картинку")
    func changeAvatarSetsAndClears() throws {
        let avatar = try Avatar.of(reference: "a.png")
        let withAvatar = Profile.empty.change(avatar: avatar)
        #expect(withAvatar.hasAvatar)
        #expect(withAvatar.change(avatar: nil).hasAvatar == false)
    }
}
