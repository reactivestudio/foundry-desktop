/// Стереотип-бин слоя Presentation (наш аналог Spring `@Controller` для MV-паттерна SwiftUI):
/// семантическая специализация `@Component` для сторов — наблюдаемых держателей состояния экрана.
/// Скан подхватывает его наравне с `@Component`. Стор обычно `@MainActor` (гонит UI) — тогда генерат
/// помечает бин `isMainActorConfined` и строит через `MainActor.assumeIsolated`, исключая из жадной
/// преинстанциации (её актор не гарантирован); эта пометка расползается по графу на всех, кто от
/// стора зависит. Скоуп — `singleton` по умолчанию (в приложении одно
/// окно на процесс); при нескольких окнах помечай `scope: .prototype`. `name` — как у `@Component`.
@attached(peer)
public macro Store(name: String? = nil, scope: Scope = .singleton) =
    #externalMacro(module: "SwiftContextMacros", type: "ComponentMacro")
