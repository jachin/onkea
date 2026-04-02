import Foundation
import OSLog
import TOMLKit

public struct HugoConfig: Decodable, Equatable {
    public var title: String?
    public var baseURL: String?
    public var languageCode: String?
    public var author: String?
    public var theme: String?
    public var canonifyURLs: Bool?
    public var copyright: String?
    public var enableRobotsTXT: Bool?
    public var params: [String: AnyCodable]?
    public var menus: [String: AnyCodable]?
    public var outputs: [String: AnyCodable]?
    public var taxonomies: [String: String]?
    public var languages: [String: AnyCodable]?
    public var permalinks: [String: String]?
    public var markup: [String: AnyCodable]?
    public var additional: [String: AnyCodable] = [:]

    public init(
        title: String? = nil,
        baseURL: String? = nil,
        languageCode: String? = nil,
        author: String? = nil,
        theme: String? = nil,
        canonifyURLs: Bool? = nil,
        copyright: String? = nil,
        enableRobotsTXT: Bool? = nil,
        params: [String: AnyCodable]? = nil,
        menus: [String: AnyCodable]? = nil,
        outputs: [String: AnyCodable]? = nil,
        taxonomies: [String: String]? = nil,
        languages: [String: AnyCodable]? = nil,
        permalinks: [String: String]? = nil,
        markup: [String: AnyCodable]? = nil,
        additional: [String: AnyCodable] = [:]
    ) {
        self.title = title
        self.baseURL = baseURL
        self.languageCode = languageCode
        self.author = author
        self.theme = theme
        self.canonifyURLs = canonifyURLs
        self.copyright = copyright
        self.enableRobotsTXT = enableRobotsTXT
        self.params = params
        self.menus = menus
        self.outputs = outputs
        self.taxonomies = taxonomies
        self.languages = languages
        self.permalinks = permalinks
        self.markup = markup
        self.additional = additional
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        title = container.decodeString(forKeys: ["title"])
        baseURL = container.decodeString(forKeys: ["baseURL", "baseurl"])
        languageCode = container.decodeString(forKeys: ["languageCode", "languagecode"])
        author = container.decodeString(forKeys: ["author"])
        theme = container.decodeTheme(forKeys: ["theme"])
        canonifyURLs = container.decodeBool(forKeys: ["canonifyURLs", "canonifyurls"])
        copyright = container.decodeString(forKeys: ["copyright"])
        enableRobotsTXT = container.decodeBool(forKeys: ["enableRobotsTXT", "enableRobotsTxt", "enableRobotstxt", "enablerobotstxt"])
        params = container.decodeDictionary(forKeys: ["params"])
        menus = container.decodeDictionary(forKeys: ["menus"])
        outputs = container.decodeDictionary(forKeys: ["outputs"])
        taxonomies = container.decodeStringDictionary(forKeys: ["taxonomies"])
        languages = container.decodeDictionary(forKeys: ["languages"])
        permalinks = container.decodeStringDictionary(forKeys: ["permalinks"])
        markup = container.decodeDictionary(forKeys: ["markup"])

        // Collect unknown keys
        let knownKeys: Set<String> = [
            "title",
            "baseURL", "baseurl",
            "languageCode", "languagecode",
            "author",
            "theme",
            "canonifyURLs", "canonifyurls",
            "copyright",
            "enableRobotsTXT", "enableRobotsTxt", "enableRobotstxt", "enablerobotstxt",
            "params",
            "menus",
            "outputs",
            "taxonomies",
            "languages",
            "permalinks",
            "markup"
        ]
        for key in container.allKeys {
            if !knownKeys.contains(key.stringValue) {
                additional[key.stringValue] = try container.decode(AnyCodable.self, forKey: key)
            }
        }
    }
}

private extension KeyedDecodingContainer where K == AnyCodingKey {
    func decodeString(forKeys keys: [String]) -> String? {
        for key in keys {
            let codingKey = AnyCodingKey(key)
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }

    func decodeTheme(forKeys keys: [String]) -> String? {
        for key in keys {
            let codingKey = AnyCodingKey(key)
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                return value
            }
            if let values = try? decodeIfPresent([String].self, forKey: codingKey),
               let firstTheme = values.first {
                return firstTheme
            }
        }
        return nil
    }

    func decodeDictionary(forKeys keys: [String]) -> [String: AnyCodable]? {
        for key in keys {
            let codingKey = AnyCodingKey(key)
            if let value = try? decodeIfPresent([String: AnyCodable].self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }

    func decodeBool(forKeys keys: [String]) -> Bool? {
        for key in keys {
            let codingKey = AnyCodingKey(key)
            if let value = try? decodeIfPresent(Bool.self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }

    func decodeStringDictionary(forKeys keys: [String]) -> [String: String]? {
        for key in keys {
            let codingKey = AnyCodingKey(key)
            if let value = try? decodeIfPresent([String: String].self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }
}

struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

public struct AnyCodable: Codable, Equatable, Hashable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let v = try? container.decode(Bool.self) {
            value = v
        } else if let v = try? container.decode(Int.self) {
            value = v
        } else if let v = try? container.decode(Double.self) {
            value = v
        } else if let v = try? container.decode(String.self) {
            value = v
        } else if let v = try? container.decode([String: AnyCodable].self) {
            value = v
        } else if let v = try? container.decode([AnyCodable].self) {
            value = v
        } else {
            value = ()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let v as Bool:
            try container.encode(v)
        case let v as Int:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as String:
            try container.encode(v)
        case let v as [String: AnyCodable]:
            try container.encode(v)
        case let v as [AnyCodable]:
            try container.encode(v)
        default:
            try container.encodeNil()
        }
    }
}

extension AnyCodable {
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case let (l as Int, r as Int): return l == r
        case let (l as String, r as String): return l == r
        case let (l as Double, r as Double): return l == r
        case let (l as Bool, r as Bool): return l == r
        case let (l as [String: AnyCodable], r as [String: AnyCodable]): return l == r
        case let (l as [AnyCodable], r as [AnyCodable]): return l == r
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch value {
        case let v as Int: hasher.combine(v)
        case let v as String: hasher.combine(v)
        case let v as Double: hasher.combine(v)
        case let v as Bool: hasher.combine(v)
        case let v as [String: AnyCodable]: hasher.combine(v)
        case let v as [AnyCodable]: hasher.combine(v)
        default: hasher.combine(0)
        }
    }
}

public func loadHugoConfigAsync(from directory: URL) async throws -> HugoConfig {
    guard let executableURL = hugoExecutableURL() else {
        throw NSError(
            domain: "HugoConfig",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not find a Hugo executable."]
        )
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["config", "--printZero", "--format", "toml"]
    process.currentDirectoryURL = directory
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    AppLogger.config.notice("Loading Hugo config via hugo CLI from \(directory.path, privacy: .public) using \(executableURL.path, privacy: .public)")

    do {
        try process.run()
    } catch {
        AppLogger.config.error("Failed to start Hugo config process: \(error.localizedDescription, privacy: .public)")
        throw error
    }

    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let standardError = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                AppLogger.config.error("Hugo config command exited with status \(process.terminationStatus). stderr: \(standardError, privacy: .public)")
                continuation.resume(
                    throwing: NSError(
                        domain: "HugoConfig",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: standardError.isEmpty ? "Hugo config command failed." : standardError]
                    )
                )
                return
            }

            guard let output = String(data: data, encoding: .utf8) else {
                AppLogger.config.error("Hugo config command produced unreadable output")
                continuation.resume(throwing: NSError(domain: "HugoConfig", code: 2, userInfo: [NSLocalizedDescriptionKey: "No output from hugo"]))
                return
            }
            // hugo --printZero splits multiple configs with null bytes.
            let configString = output.components(separatedBy: "\0").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                do {
                    let decoder = TOMLDecoder()
                    let config = try decoder.decode(HugoConfig.self, from: configString)
                    AppLogger.config.notice("Loaded Hugo config successfully from \(directory.path, privacy: .public)")
                    continuation.resume(returning: config)
                } catch {
                    AppLogger.config.error("Failed to decode hugo config command output: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(
                        throwing: NSError(
                            domain: "HugoConfig",
                            code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "The hugo config command returned output that could not be decoded: \(error.localizedDescription)"]
                        )
                    )
                }
            }
        }
    }
}
