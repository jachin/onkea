import SwiftUI

struct ContentSidebar: View {
    @Binding var isVisible: Bool
    @Binding var isSiteOpen: Bool
    @Binding var selectedPostID: String?
    @Binding var selectedTab: SidebarTab

    let isLoading: Bool
    let errorMessage: String?
    let config: HugoConfig?
    let contentItems: [HugoContentItem]
    let contentErrorMessage: String?
    let hasUnsavedChanges: (String) -> Bool
    let openSite: () -> Void
    let createSite: () -> Void

    private let expandedSidebarMinWidth: CGFloat = 320

    private var contentSections: [(section: String, items: [HugoContentItem])] {
        let grouped = Dictionary(grouping: contentItems) { $0.sectionTitle }

        return grouped
            .map { section, items in
                (
                    section,
                    items.sorted {
                        let titleComparison = $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle)
                        if titleComparison == .orderedSame {
                            return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
                        }
                        return titleComparison == .orderedAscending
                    }
                )
            }
            .sorted { $0.section.localizedCaseInsensitiveCompare($1.section) == .orderedAscending }
    }

    var body: some View {
        Group {
            if isVisible {
                expandedSidebar
                    .frame(minWidth: expandedSidebarMinWidth, idealWidth: 340, maxWidth: 420)
                    .transition(.move(edge: .leading))
            } else {
                collapsedSidebar
            }
        }
    }

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            Group {
                if !isSiteOpen {
                    closedSiteState
                } else {
                    switch selectedTab {
                    case .posts, .pages:
                        openSiteState
                    case .publishing, .siteSettings:
                        placeholderState
                    }
                }
            }
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isSiteOpen {
                HStack(spacing: 4) {
                    ForEach(SidebarTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTab == tab ? Color.primary.opacity(0.12) : .clear)
                        }
                        .help(tab.title)
                    }
                }
                .padding(4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding()
    }

    private var closedSiteState: some View {
        VStack(spacing: 16) {
            Text("No site open")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Open Site", action: openSite)
            Button("Create New Site", action: createSite)

            if isLoading {
                ProgressView("Loading site...")
                    .padding(.top)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var openSiteState: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let siteTitle = config?.title {
                Text(siteTitle)
                    .font(.title3)
                    .bold()
                    .padding(.horizontal)
            }

            if let contentErrorMessage {
                Text(contentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            List(selection: $selectedPostID) {
                ForEach(contentSections, id: \.section) { section in
                    Section(section.section) {
                        ForEach(section.items) { item in
                            ContentSidebarRow(
                                item: item,
                                hasUnsavedChanges: hasUnsavedChanges(item.id)
                            )
                            .tag(item.id as String?)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var placeholderState: some View {
        ContentUnavailableView(
            selectedTab.title,
            systemImage: selectedTab.systemImage,
            description: Text("Coming soon.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var collapsedSidebar: some View {
        EmptyView()
    }
}

private struct ContentSidebarRow: View {
    let item: HugoContentItem
    let hasUnsavedChanges: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(item.displayTitle)

            if hasUnsavedChanges {
                Circle()
                    .fill(.yellow)
                    .frame(width: 8, height: 8)
            }

            if item.isDraft {
                Text("Draft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
