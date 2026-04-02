import Foundation

struct SiteSettings: Equatable {
    var baseURL: String
    var locale: String
    var title: String
    var author: String
    var canonifyURLs: Bool
    var copyright: String
    var enableRobotsTXT: Bool

    init(
        baseURL: String = "",
        locale: String = "",
        title: String = "",
        author: String = "",
        canonifyURLs: Bool = false,
        copyright: String = "",
        enableRobotsTXT: Bool = false
    ) {
        self.baseURL = baseURL
        self.locale = locale
        self.title = title
        self.author = author
        self.canonifyURLs = canonifyURLs
        self.copyright = copyright
        self.enableRobotsTXT = enableRobotsTXT
    }

    init(config: HugoConfig) {
        self.init(
            baseURL: config.baseURL ?? "",
            locale: config.preferredLocale ?? "",
            title: config.title ?? "",
            author: config.preferredAuthorName ?? "",
            canonifyURLs: config.canonifyURLs ?? false,
            copyright: config.copyright ?? "",
            enableRobotsTXT: config.enableRobotsTXT ?? false
        )
    }
}
