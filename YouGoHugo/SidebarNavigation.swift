import Combine
import SwiftUI

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
