import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "us.rupe.Oneka"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hugo = Logger(subsystem: subsystem, category: "hugo")
    static let server = Logger(subsystem: subsystem, category: "server")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let content = Logger(subsystem: subsystem, category: "content")
    static let web = Logger(subsystem: subsystem, category: "web")
}
