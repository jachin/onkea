import Combine
import SwiftUI

extension Notification.Name {
    static let onekaOpenSiteRequested = Notification.Name("Oneka.OpenSiteRequested")
    static let onekaInsertImageRequested = Notification.Name("Oneka.InsertImageRequested")
    static let onekaInsertInternalLinkRequested = Notification.Name("Oneka.InsertInternalLinkRequested")
    static let onekaInsertDetailsShortcodeRequested = Notification.Name("Oneka.InsertDetailsShortcodeRequested")
    static let onekaInsertHighlightShortcodeRequested = Notification.Name("Oneka.InsertHighlightShortcodeRequested")
    static let onekaInsertInstagramShortcodeRequested = Notification.Name("Oneka.InsertInstagramShortcodeRequested")
    static let onekaInsertVimeoShortcodeRequested = Notification.Name("Oneka.InsertVimeoShortcodeRequested")
    static let onekaInsertYouTubeShortcodeRequested = Notification.Name("Oneka.InsertYouTubeShortcodeRequested")
    static let onekaInsertParamShortcodeRequested = Notification.Name("Oneka.InsertParamShortcodeRequested")
    static let onekaInsertQRShortcodeRequested = Notification.Name("Oneka.InsertQRShortcodeRequested")
    static let onekaInsertMarkdownAttributeRequested = Notification.Name("Oneka.InsertMarkdownAttributeRequested")
    static let onekaInsertFigureRequested = Notification.Name("Oneka.InsertFigureRequested")
}

enum SidebarTab: Int, CaseIterable, Identifiable {
    case posts = 1
    case pages
    case publishing
    case siteSettings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .posts:
            "Posts"
        case .pages:
            "Pages"
        case .publishing:
            "Publishing"
        case .siteSettings:
            "Site Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .posts:
            "doc.text"
        case .pages:
            "doc.plaintext"
        case .publishing:
            "paperplane"
        case .siteSettings:
            "gearshape"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .posts:
            "1"
        case .pages:
            "2"
        case .publishing:
            "3"
        case .siteSettings:
            "4"
        }
    }
}

enum ContentSortOrder: String, CaseIterable, Identifiable {
    case publishDateDescending
    case publishDateAscending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publishDateDescending:
            "Published Date (Newest First)"
        case .publishDateAscending:
            "Published Date (Oldest First)"
        }
    }
}

enum PostBrowseMode: String, CaseIterable, Identifiable {
    case date
    case tags
    case categories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date:
            "Date"
        case .tags:
            "Tags"
        case .categories:
            "Category"
        }
    }

    var systemImage: String {
        switch self {
        case .date:
            "calendar"
        case .tags:
            "tag"
        case .categories:
            "folder"
        }
    }
}

@MainActor
final class SidebarNavigationModel: ObservableObject {
    @Published var isSiteOpen = false
    @Published var canInsertImage = false
    @Published var canInsertInternalLink = false
    @Published var canInsertShortcode = false
    @Published var selectedTab: SidebarTab = .posts
}

struct SidebarTabCommands: Commands {
    @ObservedObject var navigationModel: SidebarNavigationModel

    var body: some Commands {
        SidebarCommands()

        CommandGroup(after: .sidebar) {
            Divider()

            ForEach(SidebarTab.allCases) { tab in
                Button(tab.title, systemImage: tab.systemImage) {
                    navigationModel.selectedTab = tab
                }
                .keyboardShortcut(tab.shortcutKey, modifiers: .command)
                .disabled(!navigationModel.isSiteOpen)
            }
        }
    }
}

struct OpenSiteCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Site...") {
                NotificationCenter.default.post(name: .onekaOpenSiteRequested, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }
    }
}

struct InsertImageCommands: Commands {
    @ObservedObject var navigationModel: SidebarNavigationModel

    var body: some Commands {
        CommandMenu("Content") {
            Button("Insert Internal Link...") {
                NotificationCenter.default.post(name: .onekaInsertInternalLinkRequested, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(!navigationModel.canInsertInternalLink)

            Button("Insert Details") {
                NotificationCenter.default.post(name: .onekaInsertDetailsShortcodeRequested, object: nil)
            }
            .disabled(!navigationModel.canInsertShortcode)

            Button("Insert Highlight") {
                NotificationCenter.default.post(name: .onekaInsertHighlightShortcodeRequested, object: nil)
            }
            .disabled(!navigationModel.canInsertShortcode)

            Button("Insert Instagram") {
                NotificationCenter.default.post(name: .onekaInsertInstagramShortcodeRequested, object: nil)
            }
            .disabled(!navigationModel.canInsertShortcode)

            Button("Insert Vimeo") {
                NotificationCenter.default.post(name: .onekaInsertVimeoShortcodeRequested, object: nil)
            }
            .disabled(!navigationModel.canInsertShortcode)

            Button("Insert YouTube") {
                NotificationCenter.default.post(name: .onekaInsertYouTubeShortcodeRequested, object: nil)
            }
            .disabled(!navigationModel.canInsertShortcode)

            Button("Insert Param") {
                NotificationCenter.default.post(name: .onekaInsertParamShortcodeRequested, object: nil)
            }
            .disabled(!navigationModel.canInsertShortcode)

            Button("Insert QR") {
                NotificationCenter.default.post(name: .onekaInsertQRShortcodeRequested, object: nil)
            }
            .disabled(!navigationModel.canInsertShortcode)

            Button("Insert Markdown Attribute") {
                NotificationCenter.default.post(name: .onekaInsertMarkdownAttributeRequested, object: nil)
            }
            .disabled(!navigationModel.canInsertShortcode)

            Button("Insert Figure...") {
                NotificationCenter.default.post(name: .onekaInsertFigureRequested, object: nil)
            }
            .disabled(!navigationModel.canInsertImage)

            Button("Insert Image...") {
                NotificationCenter.default.post(name: .onekaInsertImageRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(!navigationModel.canInsertImage)
        }
    }
}
