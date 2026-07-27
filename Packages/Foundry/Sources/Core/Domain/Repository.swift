/**
 Базовый супертип репозитория — общий словарь (в духе `Repository<T, ID>` из Spring
 Data): единый контракт хранилища агрегата по его идентичности. Агрегат связан с
 идентичностью: `Aggregate` — корень над тем же `Identifier` (`AggregateRoot<Identifier>`),
 поэтому уточнять достаточно одного типа. Конкретные репозитории не переобъявляют
 сигнатуры, а уточняют тип: `protocol PreferenceRepository: Repository where Aggregate ==
 Preference` (id выводится из агрегата). `find` опционален (нет — значит `nil`, дефолт
 подставляет use-case), `save` возвращает сохранённый агрегат.
 */
public protocol Repository {
    associatedtype Identifier: Hashable
    associatedtype Aggregate: AggregateRoot<Identifier>

    func find(id: Identifier) -> Aggregate?

    @discardableResult
    func save(entity: Aggregate) -> Aggregate
}
