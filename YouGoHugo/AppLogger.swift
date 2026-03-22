import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "us.rupe.YouGoHugo"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hugo = Logger(subsystem: subsystem, category: "hugo")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let web = Logger(subsystem: subsystem, category: "web")
}
