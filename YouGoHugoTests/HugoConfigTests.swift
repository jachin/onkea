import Foundation
import Testing
import TOMLKit
@testable import YouGoHugo

@Suite("HugoConfig Parsing and Merging")
struct HugoConfigTests {
    @Test("Basic config parses required fields")
    func parseTitleAndBaseURL() async throws {
        let toml = """
title = "My Blog"
baseURL = "https://example.com/"
"""
        let decoder = TOMLDecoder()
        let config = try decoder.decode(HugoConfig.self, from: toml)
        #expect(config.title == "My Blog")
        #expect(config.baseURL == "https://example.com/")
    }

    @Test("Merges multiple config files with precedence")
    func mergeConfigs() async throws {
        let toml1 = "title = 'First'\nbaseURL = 'http://a/'"
        let toml2 = "baseURL = 'http://b/'\nlanguageCode = 'en-us'"
        let decoder = TOMLDecoder()
        let config1 = try decoder.decode(HugoConfig.self, from: toml1)
        let config2 = try decoder.decode(HugoConfig.self, from: toml2)
        var merged = config1
        merged.merge(with: config2)
        #expect(merged.title == "First")
        #expect(merged.baseURL == "http://b/")
        #expect(merged.languageCode == "en-us")
    }

    @Test("Handles unknown keys in additional")
    func unknownKeysGoToAdditional() async throws {
        let toml = "foo = 'bar'\nmagic = 42"
        let decoder = TOMLDecoder()
        let config = try decoder.decode(HugoConfig.self, from: toml)
        #expect(config.additional["foo"] as? String == "bar")
        #expect(config.additional["magic"] as? Int == 42)
    }

    @Test("Load all TOML files and merge from directory")
    func loadAllTomlAndMerge() async throws {
        // Writes two files, loads, and merges.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tomlA = "title = 'X'\nparamA = 'A'"
        let tomlB = "baseURL = 'http://z/'\nparamB = 'B'"
        try tomlA.write(to: dir.appendingPathComponent("a.toml"), atomically: true, encoding: .utf8)
        try tomlB.write(to: dir.appendingPathComponent("b.toml"), atomically: true, encoding: .utf8)
        let loaded = try loadMergedHugoConfig(from: dir)
        #expect(loaded.title == "X")
        #expect(loaded.baseURL == "http://z/")
        #expect(loaded.additional["paramA"] as? String == "A")
        #expect(loaded.additional["paramB"] as? String == "B")
    }
}
