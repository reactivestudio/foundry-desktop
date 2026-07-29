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

        #expect(environment.property(for: "foundry.mode") == "fast")
    }

    @Test("Нет ключа — дефолт")
    func fallsBackToDefault() {
        let environment = Environment(sources: [DictionaryPropertySource(values: [:])])

        #expect(environment.string(for: "missing.key", default: "def") == "def")
    }

    @Test("env relaxed binding: foundry.storage.dir ← FOUNDRY_STORAGE_DIR")
    func relaxedEnvBinding() {
        let source = EnvironmentVariablesPropertySource(values: ["FOUNDRY_STORAGE_DIR": "/tmp/foundry"])
        let environment = Environment(sources: [source])

        #expect(environment.property(for: "foundry.storage.dir") == "/tmp/foundry")
    }

    @Test("url-геттер раскрывает значение, иначе дефолт")
    func urlGetter() {
        let fallback = URL(fileURLWithPath: "/var/default")
        let overridden = Environment(sources: [DictionaryPropertySource(values: ["dir": "/tmp/x"])])
        let empty = Environment(sources: [DictionaryPropertySource(values: [:])])

        #expect(overridden.url(for: "dir", default: fallback).path == "/tmp/x")
        #expect(empty.url(for: "dir", default: fallback) == fallback)
    }

    @Test("bool-геттер понимает истинные литералы")
    func boolGetter() {
        let environment = Environment(sources: [DictionaryPropertySource(values: ["on": "yes", "off": "0"])])

        #expect(environment.bool(for: "on", default: false))
        #expect(environment.bool(for: "off", default: true) == false)
        #expect(environment.bool(for: "absent", default: true))
    }
}
