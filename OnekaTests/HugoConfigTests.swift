import Foundation
import Testing
import TOMLKit
@testable import Oneka

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

    @Test("Handles unknown keys in additional")
    func unknownKeysGoToAdditional() async throws {
        let toml = "foo = 'bar'\nmagic = 42"
        let decoder = TOMLDecoder()
        let config = try decoder.decode(HugoConfig.self, from: toml)
        #expect(config.additional["foo"]?.value as? String == "bar")
        #expect(config.additional["magic"]?.value as? Int == 42)
    }

    @Test("Parses normalized Hugo CLI config output")
    func parsesHugoCommandOutput() async throws {
        let toml = """
title = "My Blog"
baseurl = "https://example.com/"
theme = ["paper"]

[params]
  subtitle = "Notes"
"""
        let decoder = TOMLDecoder()
        let config = try decoder.decode(HugoConfig.self, from: toml)
        #expect(config.title == "My Blog")
        #expect(config.baseURL == "https://example.com/")
        #expect(config.theme == "paper")
        #expect(config.params?["subtitle"]?.value as? String == "Notes")
    }

    @Test("Parses site settings fields used by the sidebar")
    func parsesSiteSettingsFields() async throws {
        let toml = """
title = "Jachin Rupe's Blog"
baseURL = "https://jachinrupe.name/"
languageCode = "en-us"
author = "Jachin Rupe"
canonifyurls = true
copyright = "© 2020 Jachin Rupe"
enableRobotsTXT = true
"""
        let decoder = TOMLDecoder()
        let config = try decoder.decode(HugoConfig.self, from: toml)
        #expect(config.title == "Jachin Rupe's Blog")
        #expect(config.baseURL == "https://jachinrupe.name/")
        #expect(config.languageCode == "en-us")
        #expect(config.author == "Jachin Rupe")
        #expect(config.canonifyURLs == true)
        #expect(config.copyright == "© 2020 Jachin Rupe")
        #expect(config.enableRobotsTXT == true)
    }
}
