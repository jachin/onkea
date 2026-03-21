import Foundation
import TOMLKit

public struct HugoConfig: Decodable, Equatable {
    public var title: String?
    public var baseURL: String?
    public var languageCode: String?
    public var theme: String?
    public var params: [String: AnyCodable]?
    public var menus: [String: AnyCodable]?
    public var outputs: [String: AnyCodable]?
    public var taxonomies: [String: String]?
    public var languages: [String: AnyCodable]?
    public var permalinks: [String: String]?
    public var markup: [String: AnyCodable]?
    public var additional: [String: AnyCodable] = [:]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case title, baseURL, languageCode, theme, params, menus, outputs, taxonomies, languages, permalinks, markup
    }

    public init(
        title: String? = nil,
        baseURL: String? = nil,
        languageCode: String? = nil,
        theme: String? = nil,
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
        self.theme = theme
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
        params = try container.decodeIfPresent([String: AnyCodable].self, forKey: .params)
        menus = try container.decodeIfPresent([String: AnyCodable].self, forKey: .menus)
        outputs = try container.decodeIfPresent([String: AnyCodable].self, forKey: .outputs)
        taxonomies = try container.decodeIfPresent([String: String].self, forKey: .taxonomies)
        languages = try container.decodeIfPresent([String: AnyCodable].self, forKey: .languages)
        permalinks = try container.decodeIfPresent([String: String].self, forKey: .permalinks)
        markup = try container.decodeIfPresent([String: AnyCodable].self, forKey: .markup)

        // Collect unknown keys
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let knownKeys = Set(CodingKeys.allCases.map { $0.rawValue })
        for key in raw.allKeys {
            if !knownKeys.contains(key.stringValue) {
                additional[key.stringValue] = try raw.decode(AnyCodable.self, forKey: key)
            }
        }
    }

    public mutating func merge(with other: HugoConfig) {
        if let v = other.title { self.title = v }
        if let v = other.baseURL { self.baseURL = v }
        if let v = other.languageCode { self.languageCode = v }
        if let v = other.theme { self.theme = v }
        if let v = other.params { self.params = v }
        if let v = other.menus { self.menus = v }
        if let v = other.outputs { self.outputs = v }
        if let v = other.taxonomies { self.taxonomies = v }
        if let v = other.languages { self.languages = v }
        if let v = other.permalinks { self.permalinks = v }
        if let v = other.markup { self.markup = v }
        for (k, v) in other.additional { self.additional[k] = v }
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

public func loadMergedHugoConfig(from directory: URL) throws -> HugoConfig {
    let fm = FileManager.default
    let configs = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "toml" }
    var result = HugoConfig()
    let decoder = TOMLDecoder()
    for file in configs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let content = try String(contentsOf: file, encoding: .utf8)
        let partial = try decoder.decode(HugoConfig.self, from: content)
        result.merge(with: partial)
    }
    return result
}

