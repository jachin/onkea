import Combine
import SwiftUI

extension Notification.Name {
    static let onekaOpenSiteRequested = Notification.Name("Oneka.OpenSiteRequested")
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
