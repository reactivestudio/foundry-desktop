import Foundation
import SwiftContext
import Testing

@Suite("Environment / property-source")
struct EnvironmentTests {
    @Test("Приоритет источников: первый не-nil выигрывает")
    func firstSourceWins() {
        let environment = Environment(sources: [
            DictionaryPropertySource(values: ["foundry.mode": "fast"]),
            DictionaryPropertySource(values: ["foundry.mode": "slow"]),
        ])

        #expect(environment.getProperty(name: "foundry.mode") == "fast")
    }

    @Test("Нет ключа — дефолт")
    func fallsBackToDefault() {
        let environment = Environment(sources: [DictionaryPropertySource(values: [:])])

        #expect(environment.getProperty(name: "missing.key", default: "def") == "def")
    }

    @Test("env relaxed binding: foundry.storage.dir ← FOUNDRY_STORAGE_DIR")
    func relaxedEnvBinding() {
        let source = EnvironmentVariablesPropertySource(values: ["FOUNDRY_STORAGE_DIR": "/tmp/foundry"])
        let environment = Environment(sources: [source])

        #expect(environment.getProperty(name: "foundry.storage.dir") == "/tmp/foundry")
    }

    @Test("url-геттер раскрывает значение, иначе дефолт")
    func urlGetter() {
        let fallback = URL(fileURLWithPath: "/var/default")
        let overridden = Environment(sources: [DictionaryPropertySource(values: ["dir": "/tmp/x"])])
        let empty = Environment(sources: [DictionaryPropertySource(values: [:])])

        #expect(overridden.getProperty(name: "dir", default: fallback).path == "/tmp/x")
        #expect(empty.getProperty(name: "dir", default: fallback) == fallback)
    }

    @Test("bool-геттер понимает истинные литералы")
    func boolGetter() {
        let environment = Environment(sources: [DictionaryPropertySource(values: ["on": "yes", "off": "0"])])

        #expect(environment.getProperty(name: "on", default: false))
        #expect(environment.getProperty(name: "off", default: true) == false)
        #expect(environment.getProperty(name: "absent", default: true))
    }
}

@Suite("PropertyResolver")
struct PropertyResolverTests {
    private let environment = Environment(sources: [
        DictionaryPropertySource(values: ["present": "yes"]),
    ])

    @Test("containsProperty различает «есть ключ» и «нет ключа»")
    func containsProperty() {
        #expect(environment.containsProperty(name: "present"))
        #expect(environment.containsProperty(name: "absent") == false)
    }

    @Test("getRequiredProperty: обязательная настройка падает, а не подставляет тихий дефолт")
    func requiredPropertyFailsWhenMissing() throws {
        #expect(try environment.getRequiredProperty(name: "present") == "yes")

        do {
            _ = try environment.getRequiredProperty(name: "absent")
            Issue.record("отсутствие обязательного свойства обязано упасть")
        } catch BeansException.requiredPropertyMissing(let name) {
            #expect(name == "absent")
        }
    }

    @Test("Environment годится там, где нужен только PropertyResolver")
    func environmentIsPropertyResolver() {
        // Кому нужна одна настройка — зависит от чтения, а не от устройства приоритетов источников.
        let resolver: any PropertyResolver = environment

        #expect(resolver.getProperty(name: "present", default: "no") == "yes")
    }
}
