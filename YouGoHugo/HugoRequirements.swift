import Foundation
import OSLog

private let fallbackHugoExecutablePaths = [
    "/opt/homebrew/bin/hugo",
    "/usr/local/bin/hugo",
    "/usr/bin/hugo"
]

func hugoExecutableURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
) -> URL? {
    if let configuredPath = environment["HUGO_EXECUTABLE"],
       let executableURL = candidateExecutableURL(atPath: configuredPath, fileManager: fileManager) {
        AppLogger.hugo.notice("Using Hugo executable from HUGO_EXECUTABLE at \(executableURL.path, privacy: .public)")
        return executableURL
    }

    let pathDirectories = environment["PATH"]?
        .split(separator: ":")
        .map(String.init) ?? []

    for directory in pathDirectories {
        let candidatePath = URL(fileURLWithPath: directory).appendingPathComponent("hugo").path
        if let executableURL = candidateExecutableURL(atPath: candidatePath, fileManager: fileManager) {
            AppLogger.hugo.notice("Using Hugo executable from PATH at \(executableURL.path, privacy: .public)")
            return executableURL
        }
    }

    for candidatePath in fallbackHugoExecutablePaths {
        AppLogger.hugo.notice("Checking fallback Hugo path \(candidatePath, privacy: .public)")
        if let executableURL = candidateExecutableURL(atPath: candidatePath, fileManager: fileManager) {
            AppLogger.hugo.notice("Using Hugo executable from fallback path at \(executableURL.path, privacy: .public)")
            return executableURL
        }
    }

    AppLogger.hugo.error("Failed to find Hugo executable. PATH was \(environment["PATH"] ?? "<missing>", privacy: .public)")
    return nil
}

private func candidateExecutableURL(atPath path: String, fileManager: FileManager) -> URL? {
    let url = URL(fileURLWithPath: path)
    let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    if fileManager.isExecutableFile(atPath: path) {
        return url
    }

    if resolvedPath != path, fileManager.isExecutableFile(atPath: resolvedPath) {
        AppLogger.hugo.notice("Resolved symlinked Hugo executable from \(path, privacy: .public) to \(resolvedPath, privacy: .public)")
        return URL(fileURLWithPath: resolvedPath)
    }

    if fileManager.fileExists(atPath: path) {
        AppLogger.hugo.notice("Found Hugo candidate at \(path, privacy: .public) but it is not marked executable")
        return url
    }

    if resolvedPath != path, fileManager.fileExists(atPath: resolvedPath) {
        AppLogger.hugo.notice("Resolved Hugo symlink from \(path, privacy: .public) to existing target \(resolvedPath, privacy: .public)")
        return URL(fileURLWithPath: resolvedPath)
    }

    return nil
}

public func checkHugoVersion() async throws -> HugoVersion {
    guard let executableURL = hugoExecutableURL() else {
        throw NSError(
            domain: "HugoVersion",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not find a Hugo executable."]
        )
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["version"]
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    AppLogger.hugo.notice("Running Hugo version check with \(executableURL.path, privacy: .public)")

    do {
        try process.run()
    } catch {
        AppLogger.hugo.error("Failed to start Hugo version check: \(error.localizedDescription, privacy: .public)")
        throw error
    }

    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let standardError = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                AppLogger.hugo.error("Hugo version check exited with status \(process.terminationStatus). stderr: \(standardError, privacy: .public)")
                continuation.resume(
                    throwing: NSError(
                        domain: "HugoVersion",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: standardError.isEmpty ? "Hugo version check failed." : standardError]
                    )
                )
                return
            }

            guard let output = String(data: data, encoding: .utf8) else {
                AppLogger.hugo.error("Hugo version check produced unreadable output")
                continuation.resume(throwing: NSError(domain: "HugoVersion", code: 1, userInfo: [NSLocalizedDescriptionKey: "No output from hugo"]))
                return
            }
            if let version = HugoVersion(output) {
                AppLogger.hugo.notice("Resolved Hugo version \(version.versionString, privacy: .public)")
                continuation.resume(returning: version)
            } else {
                AppLogger.hugo.error("Could not parse Hugo version output: \(output, privacy: .public)")
                continuation.resume(throwing: NSError(domain: "HugoVersion", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not parse version string: \(output)"]))
            }
        }
    }
}
