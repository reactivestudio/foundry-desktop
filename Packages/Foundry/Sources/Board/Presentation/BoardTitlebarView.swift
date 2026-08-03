import Core
import SwiftUI

/**
 Титлбар окна: имя выбранного проекта и два действия.

 Плашки у титлбара нет вовсе — он стоит на фоне окна, и светофор системный.
 Своего поля у него тоже нет: он живёт в поле окна, и потому светофор занимает
 ровно плиту рейла, а заголовок встаёт на флаг сайдбара. Действия справа
 стоят на правой кромке канваса.

 Главное действие названо СЛОВОМ, а не одним плюсом: на пустой доске оно
 зовётся «Новый change», и безымянная иконка в титлбаре была бы тем же
 действием под другим именем. Лупа остаётся иконкой — поиск опознаётся
 без подписи, а создание нет.

 Заголовок называет тот проект, который выбран в сайдбаре: жёсткое имя
 спорило бы с подсветкой в списке слева.
 */
struct BoardTitlebarView: View {
    let project: String

    var body: some View {
        HStack(spacing: Token.Space.step3) {
            // Место светофора: кнопки рисует AppKit, здесь только их полоса.
            Text(project)
                .typography(BoardType.bodyMedium)
                .foregroundStyle(Token.Text.secondary)
                .padding(.leading, BoardMetrics.titleLeading)
            Spacer(minLength: Token.Space.step4)
            TitlebarActionView(symbol: "magnifyingglass", title: "Поиск", key: "⌘K")
            TitlebarActionView(symbol: "plus", title: "Новый change", key: "⌘N")
        }
        .frame(height: BoardMetrics.titlebarHeight)
    }
}

/// Действие титлбара: знак, слово и сочетание клавиш.
///
/// Клавиша стоит РЯДОМ С ДЕЙСТВИЕМ, а не в подсказке по наведению: подсказка
/// называет клавишу тому, кто уже знает, куда наводить. Набрана она тем же
/// шрифтом, что и всё вокруг: клавиша — не код, поэтому не моноширинная.
private struct TitlebarActionView: View {
    let symbol: String
    let title: String
    let key: String

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Token.Space.step1 + 2) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 13, height: 13)
            Text(title)
                .typography(Token.Typography.body)
            Text(key)
                .typography(BoardType.key)
                .foregroundStyle(Token.Text.tertiary)
                .opacity(0.85)
                // Клавиша отбита от слова вдвое против знака: она поясняет
                // действие, а знак его называет вместе со словом.
                .padding(.leading, Token.Space.step1 + 2)
        }
        .foregroundStyle(isHovered ? Token.Text.primary : Token.Text.secondary)
        .padding(.leading, Token.Space.step2)
        .padding(.trailing, Token.Space.step2 + 2)
        .frame(height: Token.Control.hCompact)
        .background(isHovered ? BoardPalette.card : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .animation(AppMotion.hover(isHovered), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(.isButton)
    }
}
