import Foundation
import OSLog

/// The minimum required Hugo version for compatibility checks.
/// e.g., "0.158.0"
public let minimumHugoVersion = HugoVersion(major: 0, minor: 158, patch: 0)

// Represents a semantic version for Hugo (e.g., v0.158.0)
public struct HugoVersion: Comparable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: HugoVersion, rhs: HugoVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ string: String) {
        var str = string
        if str.hasPrefix("v") { str.removeFirst() }
        let comps = str.split(separator: ".", omittingEmptySubsequences: false)
        guard comps.count >= 3 else { return nil }
        self.major = Int(comps[0]) ?? 0
        self.minor = Int(comps[1]) ?? 0
        // Support trailing + or other build info after patch
        let patchPart = comps[2].split(separator: "+").first ?? comps[2]
        self.patch = Int(patchPart) ?? 0
    }
    
    public var versionString: String { description }
}

// Enum representing the state of Hugo on the system
public enum HugoStatus: Equatable {
    case checking
    case notInstalled
    case incompatibleVersion(found: HugoVersion)
    case compatible
}

public struct HugoContentItem: Identifiable, Equatable, Hashable {
    public let path: String
    public let slug: String
    public let title: String
    public let date: String
    public let expiryDate: String
    public let publishDate: String
    public let isDraft: Bool
    public let permalink: String
    public let kind: String
    public let section: String

    public var id: String { path }

    public var displayTitle: String {
        if !title.isEmpty {
            return title
        }

        let fallback = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return fallback.isEmpty ? path : fallback
    }

    public var sectionTitle: String {
        section.isEmpty ? "Ungrouped" : section
    }
}

public struct HugoContentMetadata: Equatable, Hashable {
    public let tags: [String]
    public let categories: [String]
    public let publishDate: Date?
}

public struct HugoContentMetadataDatabase: Equatable {
    public var metadataByID: [String: HugoContentMetadata]
    public var itemIDsByTag: [String: Set<String>]
    public var itemIDsByCategory: [String: Set<String>]

    public init(
        metadataByID: [String: HugoContentMetadata] = [:],
        itemIDsByTag: [String: Set<String>] = [:],
        itemIDsByCategory: [String: Set<String>] = [:]
    ) {
        self.metadataByID = metadataByID
        self.itemIDsByTag = itemIDsByTag
        self.itemIDsByCategory = itemIDsByCategory
    }

    public func metadata(for itemID: String) -> HugoContentMetadata? {
        metadataByID[itemID]
    }

    public func itemIDs(taggedWith tag: String) -> Set<String> {
        itemIDsByTag[tag.normalizedMetadataKey] ?? []
    }

    public func itemIDs(inCategory category: String) -> Set<String> {
        itemIDsByCategory[category.normalizedMetadataKey] ?? []
    }
}

public func loadHugoContentMetadataDatabaseAsync(
    from directory: URL,
    items: [HugoContentItem]
) async throws -> HugoContentMetadataDatabase {
    var metadataByID: [String: HugoContentMetadata] = [:]
    var itemIDsByTag: [String: Set<String>] = [:]
    var itemIDsByCategory: [String: Set<String>] = [:]

    for item in items {
        let fileURL = directory.appendingPathComponent(item.path)
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let metadata = parseHugoContentMetadata(from: source, fallbackItem: item)

        metadataByID[item.id] = metadata

        for tag in metadata.tags {
            itemIDsByTag[tag.normalizedMetadataKey, default: []].insert(item.id)
        }

        for category in metadata.categories {
            itemIDsByCategory[category.normalizedMetadataKey, default: []].insert(item.id)
        }
    }

    return HugoContentMetadataDatabase(
        metadataByID: metadataByID,
        itemIDsByTag: itemIDsByTag,
        itemIDsByCategory: itemIDsByCategory
    )
}

public func loadHugoContentListAsync(from directory: URL) async throws -> [HugoContentItem] {
    guard let executableURL = hugoExecutableURL() else {
        throw NSError(
            domain: "HugoContent",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not find a Hugo executable."]
        )
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["list", "all"]
    process.currentDirectoryURL = directory
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    AppLogger.content.notice("Loading Hugo content list from \(directory.path, privacy: .public) using \(executableURL.path, privacy: .public)")

    do {
        try process.run()
    } catch {
        AppLogger.content.error("Failed to start Hugo list process: \(error.localizedDescription, privacy: .public)")
        throw error
    }

    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let standardError = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                AppLogger.content.error("Hugo list command exited with status \(process.terminationStatus). stderr: \(standardError, privacy: .public)")
                continuation.resume(
                    throwing: NSError(
                        domain: "HugoContent",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: standardError.isEmpty ? "Hugo list command failed." : standardError]
                    )
                )
                return
            }

            guard let output = String(data: data, encoding: .utf8) else {
                AppLogger.content.error("Hugo list command produced unreadable output")
                continuation.resume(
                    throwing: NSError(
                        domain: "HugoContent",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No output from hugo list."]
                    )
                )
                return
            }

            do {
                let items = try parseHugoContentList(output)
                AppLogger.content.notice("Loaded \(items.count, privacy: .public) Hugo content items")
                continuation.resume(returning: items)
            } catch {
                AppLogger.content.error("Failed to parse hugo list output: \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: error)
            }
        }
    }
}

public func loadContentBodyAsync(from directory: URL, relativePath: String) async throws -> String {
    let fileURL = directory.appendingPathComponent(relativePath)
    AppLogger.content.notice("Loading content body from \(fileURL.path, privacy: .public)")
    return try await Task.detached(priority: .userInitiated) {
        try String(contentsOf: fileURL, encoding: .utf8)
    }.value
}

func parseHugoContentMetadata(from source: String, fallbackItem: HugoContentItem? = nil) -> HugoContentMetadata {
    let parsedFrontMatter = parseFrontMatterMetadata(from: source)

    let tags = parsedFrontMatter?[MetadataField.tags.rawValue] ?? []
    let categories = parsedFrontMatter?[MetadataField.categories.rawValue]
        ?? parsedFrontMatter?[MetadataField.category.rawValue]
        ?? []
    let publishDate = parsedFrontMatter?[MetadataField.publishDate.rawValue]?.first.flatMap(parseMetadataDate)
        ?? parsedFrontMatter?[MetadataField.date.rawValue]?.first.flatMap(parseMetadataDate)
        ?? fallbackItem?.publishDate.nonEmpty.flatMap(parseMetadataDate)
        ?? fallbackItem?.date.nonEmpty.flatMap(parseMetadataDate)

    return HugoContentMetadata(
        tags: normalizedMetadataValues(tags),
        categories: normalizedMetadataValues(categories),
        publishDate: publishDate
    )
}

func parseHugoContentList(_ output: String) throws -> [HugoContentItem] {
    let rows = output
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        .filter { !$0.isEmpty }

    guard let headerLine = rows.first else {
        return []
    }

    let headers = parseCSVRow(headerLine)
    guard !headers.isEmpty else {
        throw NSError(
            domain: "HugoContent",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Hugo list output did not include a header row."]
        )
    }

    return try rows.dropFirst().map { row in
        let values = parseCSVRow(row)
        guard values.count == headers.count else {
            throw NSError(
                domain: "HugoContent",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected hugo list row format."]
            )
        }

        let mapped = Dictionary(uniqueKeysWithValues: zip(headers, values))
        let path = mapped["path"] ?? ""

        guard !path.isEmpty else {
            throw NSError(
                domain: "HugoContent",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Encountered a Hugo content row without a path."]
            )
        }

        return HugoContentItem(
            path: path,
            slug: mapped["slug"] ?? "",
            title: mapped["title"] ?? "",
            date: mapped["date"] ?? "",
            expiryDate: mapped["expiryDate"] ?? "",
            publishDate: mapped["publishDate"] ?? "",
            isDraft: (mapped["draft"] ?? "").lowercased() == "true",
            permalink: mapped["permalink"] ?? "",
            kind: mapped["kind"] ?? "",
            section: mapped["section"] ?? ""
        )
    }
}

private func parseCSVRow(_ row: String) -> [String] {
    var fields: [String] = []
    var currentField = ""
    var isInsideQuotes = false
    let characters = Array(row)
    var index = 0

    while index < characters.count {
        let character = characters[index]

        if character == "\"" {
            if isInsideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                currentField.append("\"")
                index += 1
            } else {
                isInsideQuotes.toggle()
            }
        } else if character == ",", !isInsideQuotes {
            fields.append(currentField)
            currentField = ""
        } else {
            currentField.append(character)
        }

        index += 1
    }

    fields.append(currentField)
    return fields
}

private enum FrontMatterFormat {
    case yaml
    case toml
    case json
}

private enum MetadataField: String, CaseIterable {
    case tags
    case categories
    case category
    case publishDate = "publishdate"
    case date
}

private func parseFrontMatterMetadata(from source: String) -> [String: [String]]? {
    let sanitizedSource = source.removingUTF8BOM
    let trimmedSource = sanitizedSource.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSource.isEmpty else {
        return nil
    }

    if sanitizedSource.hasPrefix("---\n") || sanitizedSource == "---" || sanitizedSource.hasPrefix("---\r\n") {
        return parseDelimitedFrontMatterMetadata(in: sanitizedSource, delimiter: "---", format: .yaml)
    }

    if sanitizedSource.hasPrefix("+++\n") || sanitizedSource == "+++" || sanitizedSource.hasPrefix("+++\r\n") {
        return parseDelimitedFrontMatterMetadata(in: sanitizedSource, delimiter: "+++", format: .toml)
    }

    if trimmedSource.first == "{" {
        return parseJSONFrontMatterMetadata(from: sanitizedSource)
    }

    return nil
}

private func parseDelimitedFrontMatterMetadata(
    in source: String,
    delimiter: String,
    format: FrontMatterFormat
) -> [String: [String]]? {
    let normalizedSource = source.replacingOccurrences(of: "\r\n", with: "\n")
    let prefix = "\(delimiter)\n"
    guard normalizedSource.hasPrefix(prefix) else {
        return nil
    }

    let bodyStart = normalizedSource.index(normalizedSource.startIndex, offsetBy: prefix.count)
    guard let closingRange = normalizedSource[bodyStart...].range(of: "\n\(delimiter)") else {
        return nil
    }

    let metadataBlock = String(normalizedSource[bodyStart..<closingRange.lowerBound])
    switch format {
    case .yaml:
        return parseYAMLFrontMatterMetadataBlock(metadataBlock)
    case .toml:
        return parseTOMLFrontMatterMetadataBlock(metadataBlock)
    case .json:
        return nil
    }
}

private func parseYAMLFrontMatterMetadataBlock(_ block: String) -> [String: [String]] {
    var metadata: [String: [String]] = [:]
    let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var currentKey: String?

    for rawLine in lines {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            continue
        }

        if let currentKey, trimmed.hasPrefix("- ") {
            let value = String(trimmed.dropFirst(2))
            let normalizedValue = trimMetadataValue(value)
            if !normalizedValue.isEmpty {
                metadata[currentKey, default: []].append(normalizedValue)
            }
            continue
        }

        guard let separatorIndex = rawLine.firstIndex(of: ":") else {
            currentKey = nil
            continue
        }

        let key = rawLine[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = rawLine[rawLine.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let field = MetadataField(rawValue: key) else {
            currentKey = nil
            continue
        }

        currentKey = field.rawValue
        if value.isEmpty {
            metadata[currentKey!, default: []] = metadata[currentKey!] ?? []
            continue
        }

        metadata[currentKey!] = parseMetadataValueList(String(value))
    }

    return metadata
}

private func parseTOMLFrontMatterMetadataBlock(_ block: String) -> [String: [String]] {
    var metadata: [String: [String]] = [:]
    let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var lineIndex = 0

    while lineIndex < lines.count {
        let line = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("[") else {
            lineIndex += 1
            continue
        }

        guard let separatorIndex = line.firstIndex(of: "=") else {
            lineIndex += 1
            continue
        }

        let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let field = MetadataField(rawValue: key) else {
            lineIndex += 1
            continue
        }

        var value = String(line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines))

        if value == "[" {
            var collectedLines: [String] = [value]
            lineIndex += 1

            while lineIndex < lines.count {
                let continuedLine = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                collectedLines.append(continuedLine)
                if continuedLine == "]" || continuedLine.hasSuffix("]") {
                    break
                }
                lineIndex += 1
            }

            value = collectedLines.joined(separator: " ")
        }

        metadata[field.rawValue] = parseMetadataValueList(value)
        lineIndex += 1
    }

    return metadata
}

private func parseJSONFrontMatterMetadata(from source: String) -> [String: [String]]? {
    let normalizedSource = source.replacingOccurrences(of: "\r\n", with: "\n")
    let scalars = Array(normalizedSource)
    guard let closingIndex = endIndexOfTopLevelJSONObject(in: scalars) else {
        return nil
    }

    let jsonText = String(scalars[...closingIndex])
    guard let data = jsonText.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    let normalizedObject = Dictionary(
        uniqueKeysWithValues: object.map { key, value in
            (key.lowercased(), value)
        }
    )
    var metadata: [String: [String]] = [:]
    for field in MetadataField.allCases {
        guard let value = normalizedObject[field.rawValue] else {
            continue
        }

        metadata[field.rawValue] = parseMetadataValueList(fromJSONObject: value)
    }
    return metadata
}

private func endIndexOfTopLevelJSONObject(in characters: [Character]) -> Int? {
    var depth = 0
    var isInsideString = false
    var isEscaped = false

    for (index, character) in characters.enumerated() {
        if isInsideString {
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isInsideString = false
            }
            continue
        }

        if character == "\"" {
            isInsideString = true
            continue
        }

        if character == "{" {
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0 {
                return index
            }
        }
    }

    return nil
}

private func parseMetadataValueList(_ rawValue: String) -> [String] {
    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return []
    }

    if trimmedValue.first == "[", trimmedValue.last == "]" {
        let innerValue = String(trimmedValue.dropFirst().dropLast())
        return splitDelimitedMetadataList(innerValue)
            .map(trimMetadataValue)
            .filter { !$0.isEmpty }
    }

    return [trimMetadataValue(trimmedValue)].filter { !$0.isEmpty }
}

private func parseMetadataValueList(fromJSONObject value: Any) -> [String] {
    if let values = value as? [Any] {
        return values.compactMap { element in
            if let stringValue = element as? String {
                return trimMetadataValue(stringValue)
            }

            if let numberValue = element as? NSNumber {
                return numberValue.stringValue
            }

            return nil
        }
    }

    if let stringValue = value as? String {
        return parseMetadataValueList(stringValue)
    }

    if let numberValue = value as? NSNumber {
        return [numberValue.stringValue]
    }

    return []
}

private func splitDelimitedMetadataList(_ source: String) -> [String] {
    var values: [String] = []
    var currentValue = ""
    var inQuotes = false
    var quoteCharacter: Character?

    for character in source {
        if character == "\"" || character == "'" {
            if inQuotes, quoteCharacter == character {
                inQuotes = false
                quoteCharacter = nil
            } else if !inQuotes {
                inQuotes = true
                quoteCharacter = character
            }
        }

        if character == ",", !inQuotes {
            values.append(currentValue)
            currentValue = ""
            continue
        }

        currentValue.append(character)
    }

    values.append(currentValue)
    return values
}

private func trimMetadataValue(_ value: String) -> String {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedValue.count >= 2 else {
        return trimmedValue
    }

    if (trimmedValue.first == "\"" && trimmedValue.last == "\"")
        || (trimmedValue.first == "'" && trimmedValue.last == "'") {
        return String(trimmedValue.dropFirst().dropLast())
    }

    return trimmedValue
}

private func normalizedMetadataValues(_ values: [String]) -> [String] {
    var seen: Set<String> = []

    return values.compactMap { value in
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = trimmedValue.normalizedMetadataKey
        guard !trimmedValue.isEmpty, !seen.contains(normalizedKey) else {
            return nil
        }

        seen.insert(normalizedKey)
        return trimmedValue
    }
}

private func parseMetadataDate(_ value: String) -> Date? {
    let trimmedValue = trimMetadataValue(value)
    guard !trimmedValue.isEmpty else {
        return nil
    }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: trimmedValue) {
        return date
    }

    isoFormatter.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: trimmedValue) {
        return date
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)

    let formats = [
        "yyyy-MM-dd",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    ]

    for format in formats {
        formatter.dateFormat = format
        if let date = formatter.date(from: trimmedValue) {
            return date
        }
    }

    return nil
}

private extension String {
    var removingUTF8BOM: String {
        hasPrefix("\u{FEFF}") ? String(dropFirst()) : self
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedMetadataKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
