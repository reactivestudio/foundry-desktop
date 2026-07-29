/**
 `BeanDefinitionHolder` — определение бина вместе с его именем (точное имя из Spring). Имя это ключ
 реестра, а не поле `BeanDefinition` (см. `BeanDefinition`), поэтому кодоген отдаёт определения
 обёрнутыми в холдер, а `ApplicationContext` регистрирует их в `BeanDefinitionRegistry`. Аналог
 того, что сканер класспаса Spring отдаёт набором `BeanDefinitionHolder`.
 */
public struct BeanDefinitionHolder {
    public let name: String
    public let definition: BeanDefinition

    public init(name: String, definition: BeanDefinition) {
        self.name = name
        self.definition = definition
    }
}
