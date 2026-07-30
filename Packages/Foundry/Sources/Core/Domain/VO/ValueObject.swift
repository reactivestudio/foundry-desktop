/**
 Роль value object'а — общий словарь тактического DDD. Иммутабельная `struct`,
 равенство по значению (`Equatable`), без identity; собирается фабрикой `of`, которая
 гарантирует инварианты (невалидный VO не рождается). `Sendable` — VO безопасно
 пересекает акторы. Один тип — один файл.
 */
public protocol ValueObject: Equatable, Sendable {}
