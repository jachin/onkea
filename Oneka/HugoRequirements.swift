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

struct HugoServerParseState {
    var currentServerURL: URL?
    var currentStatus = HugoServerStatus(phase: .starting, message: "Starting Hugo server…", serverURL: nil)
    var isBuilding = false
}

func nextHugoServerStatus(for rawLine: String, isError: Bool, state: inout HugoServerParseState) -> HugoServerStatus? {
    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return nil }

    if let serverURL = extractHugoServerURL(from: line) {
        state.currentServerURL = serverURL

        if state.isBuilding {
            state.currentStatus = HugoServerStatus(
                phase: .building,
                message: state.currentStatus.message,
                serverURL: serverURL
            )
        } else {
            state.currentStatus = HugoServerStatus(
                phase: .serving,
                message: "Serving at \(serverURL.absoluteString)",
                serverURL: serverURL
            )
        }

        return state.currentStatus
    }

    if line.localizedCaseInsensitiveContains("Start building sites") {
        state.isBuilding = true
        state.currentStatus = HugoServerStatus(
            phase: .building,
            message: "Building site…",
            serverURL: state.currentServerURL
        )
        return state.currentStatus
    }

    if line.localizedCaseInsensitiveContains("Change detected, rebuilding site") {
        state.isBuilding = true
        state.currentStatus = HugoServerStatus(
            phase: .building,
            message: line,
            serverURL: state.currentServerURL
        )
        return state.currentStatus
    }

    if state.isBuilding, line.localizedCaseInsensitiveContains("Source changed") {
        state.currentStatus = HugoServerStatus(
            phase: .building,
            message: line,
            serverURL: state.currentServerURL
        )
        return state.currentStatus
    }

    if line.localizedCaseInsensitiveContains("Built in") || line.localizedCaseInsensitiveContains("Total in") {
        state.isBuilding = false
        state.currentStatus = HugoServerStatus(
            phase: .serving,
            message: line,
            serverURL: state.currentServerURL
        )
        return state.currentStatus
    }

    if line.localizedCaseInsensitiveContains("port") &&
        line.localizedCaseInsensitiveContains("already in use") {
        state.isBuilding = false
        state.currentStatus = HugoServerStatus(
            phase: .warning,
            message: line,
            serverURL: state.currentServerURL
        )
        return state.currentStatus
    }

    if line.localizedCaseInsensitiveContains("Watching for changes") {
        state.currentStatus = HugoServerStatus(
            phase: .starting,
            message: "Watching for changes…",
            serverURL: state.currentServerURL
        )
        return state.currentStatus
    }

    if line.localizedCaseInsensitiveContains("Press Ctrl+C to stop") {
        state.isBuilding = false
        state.currentStatus = HugoServerStatus(
            phase: .serving,
            message: "Server running",
            serverURL: state.currentServerURL
        )
        return state.currentStatus
    }

    if isError || line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("failed") {
        state.isBuilding = false
        state.currentStatus = HugoServerStatus(
            phase: .failed,
            message: line,
            serverURL: state.currentServerURL
        )
        return state.currentStatus
    }

    if state.currentStatus.phase == .starting {
        state.currentStatus = HugoServerStatus(
            phase: .starting,
            message: line,
            serverURL: state.currentServerURL
        )
        return state.currentStatus
    }

    return nil
}

private func extractHugoServerURL(from line: String) -> URL? {
    let marker = "Web Server is available at "
    guard let range = line.range(of: marker) else {
        return nil
    }

    let remainder = line[range.upperBound...]
    let urlText = remainder.split(separator: " ").first.map(String.init) ?? String(remainder)
    return URL(string: urlText.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
}

private final class HugoServerOutputParser {
    private var buffer = ""
    private var state = HugoServerParseState()
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

        guard let status = nextHugoServerStatus(for: line, isError: isError, state: &state) else {
            return
        }

        Task { @MainActor in
            statusHandler(status)
        }
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
