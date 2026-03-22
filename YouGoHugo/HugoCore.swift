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
