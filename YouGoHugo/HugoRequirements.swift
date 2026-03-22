import Foundation
import OSLog

private let fallbackHugoExecutablePaths = [
    "/opt/homebrew/bin/hugo",
    "/usr/local/bin/hugo",
    "/usr/bin/hugo"
]

private let hugoServerArguments = [
    "server",
    "--noHTTPCache",
    "--buildDrafts",
    "--buildExpired",
    "--buildFuture"
]

public enum HugoServerPhase: Equatable {
    case stopped
    case starting
    case building
    case serving
    case warning
    case failed
}

public struct HugoServerStatus: Equatable {
    public let phase: HugoServerPhase
    public let message: String
    public let serverURL: URL?

    public init(phase: HugoServerPhase, message: String, serverURL: URL? = nil) {
        self.phase = phase
        self.message = message
        self.serverURL = serverURL
    }
}

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

private final class HugoServerOutputParser {
    private var buffer = ""
    private var currentServerURL: URL?
    private let statusHandler: @MainActor (HugoServerStatus) -> Void

    init(statusHandler: @escaping @MainActor (HugoServerStatus) -> Void) {
        self.statusHandler = statusHandler
    }

    func ingest(_ data: Data, isError: Bool) {
        guard !data.isEmpty, let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return
        }

        buffer += output
        let lines = buffer.components(separatedBy: .newlines)
        buffer = lines.last ?? ""

        for line in lines.dropLast() {
            handleLine(line, isError: isError)
        }
    }

    func finish() {
        let trailingLine = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailingLine.isEmpty {
            handleLine(trailingLine, isError: false)
        }
        buffer = ""
    }

    private func handleLine(_ rawLine: String, isError: Bool) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        if isError {
            AppLogger.server.error("Hugo server stderr: \(line, privacy: .public)")
        } else {
            AppLogger.server.notice("Hugo server stdout: \(line, privacy: .public)")
        }

        Task { @MainActor in
            statusHandler(status(for: line, isError: isError))
        }
    }

    private func status(for line: String, isError: Bool) -> HugoServerStatus {
        if let serverURL = extractServerURL(from: line) {
            currentServerURL = serverURL
            return HugoServerStatus(
                phase: .serving,
                message: "Serving at \(serverURL.absoluteString)",
                serverURL: serverURL
            )
        }

        if line.localizedCaseInsensitiveContains("Start building sites") {
            return HugoServerStatus(phase: .building, message: "Building site…", serverURL: currentServerURL)
        }

        if line.localizedCaseInsensitiveContains("Built in") {
            return HugoServerStatus(phase: .serving, message: line, serverURL: currentServerURL)
        }

        if line.localizedCaseInsensitiveContains("port") &&
            line.localizedCaseInsensitiveContains("already in use") {
            return HugoServerStatus(phase: .warning, message: line, serverURL: currentServerURL)
        }

        if line.localizedCaseInsensitiveContains("Watching for changes") {
            return HugoServerStatus(phase: .starting, message: "Watching for changes…", serverURL: currentServerURL)
        }

        if line.localizedCaseInsensitiveContains("Press Ctrl+C to stop") {
            return HugoServerStatus(phase: .serving, message: "Server running", serverURL: currentServerURL)
        }

        if isError || line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("failed") {
            return HugoServerStatus(phase: .failed, message: line, serverURL: currentServerURL)
        }

        return HugoServerStatus(phase: .starting, message: line, serverURL: currentServerURL)
    }

    private func extractServerURL(from line: String) -> URL? {
        let marker = "Web Server is available at "
        guard let range = line.range(of: marker) else {
            return nil
        }

        let remainder = line[range.upperBound...]
        let urlText = remainder.split(separator: " ").first.map(String.init) ?? String(remainder)
        return URL(string: urlText.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }
}

public func startHugoServer(
    from directory: URL,
    statusHandler: @escaping @MainActor (HugoServerStatus) -> Void
) throws -> Process {
    guard let executableURL = hugoExecutableURL() else {
        throw NSError(
            domain: "HugoServer",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not find a Hugo executable."]
        )
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = hugoServerArguments
    process.currentDirectoryURL = directory

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    let parser = HugoServerOutputParser(statusHandler: statusHandler)

    outputPipe.fileHandleForReading.readabilityHandler = { handle in
        parser.ingest(handle.availableData, isError: false)
    }

    errorPipe.fileHandleForReading.readabilityHandler = { handle in
        parser.ingest(handle.availableData, isError: true)
    }

    process.terminationHandler = { terminatedProcess in
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        parser.finish()
        AppLogger.server.notice("Hugo server exited with status \(terminatedProcess.terminationStatus)")
        Task { @MainActor in
            statusHandler(
                HugoServerStatus(
                    phase: terminatedProcess.terminationStatus == 0 ? .stopped : .failed,
                    message: terminatedProcess.terminationStatus == 0 ? "Server stopped" : "Server exited with status \(terminatedProcess.terminationStatus)",
                    serverURL: nil
                )
            )
        }
    }

    AppLogger.server.notice(
        "Starting Hugo server in \(directory.path, privacy: .public) with arguments \(hugoServerArguments.joined(separator: " "), privacy: .public)"
    )

    do {
        Task { @MainActor in
            statusHandler(HugoServerStatus(phase: .starting, message: "Starting Hugo server…", serverURL: nil))
        }
        try process.run()
        return process
    } catch {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        AppLogger.server.error("Failed to start Hugo server: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            statusHandler(HugoServerStatus(phase: .failed, message: "Failed to start Hugo server: \(error.localizedDescription)", serverURL: nil))
        }
        throw error
    }
}

public func stopHugoServer(_ process: Process?) {
    guard let process else { return }
    guard process.isRunning else { return }

    AppLogger.server.notice("Stopping Hugo server")
    process.terminate()
}
