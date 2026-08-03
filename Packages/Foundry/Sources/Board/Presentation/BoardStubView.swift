import Core
import SwiftUI

/**
 Раздел, которого ещё нет.

 Говорит ровно то, что есть, и не притворяется пустым состоянием: пустое
 состояние — это когда данных нет, а тут нет самого раздела. Разница
 существенная: пустое состояние зовёт завести первый объект, а этот экран
 звать некуда, и кнопка на нём была бы обещанием, которого продукт
 не выполнит.
 */
struct BoardStubView: View {
    let section: BoardSection

    var body: some View {
        VStack(spacing: Token.Space.step2) {
            Text(section.title)
                .font(.system(size: Token.Typography.heading.size, weight: .semibold))
                .foregroundStyle(Token.Text.secondary)
            Text("Раздел ещё не сделан")
                .font(.system(size: 13))
                .foregroundStyle(Token.Text.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardPalette.plate)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.extraLarge, style: .continuous))
    }
}
