import SwiftUI

struct ContentSidebar: View {
    @Binding var isVisible: Bool
    @Binding var isSiteOpen: Bool
    @Binding var selectedPostID: String?
    @Binding var selectedTab: SidebarTab
    @Binding var sortOrder: ContentSortOrder
    @Binding var postBrowseMode: PostBrowseMode
    @Binding var siteSettings: SiteSettings

    let isLoading: Bool
    let errorMessage: String?
    let config: HugoConfig?
    let contentItems: [HugoContentItem]
    let contentMetadataDatabase: HugoContentMetadataDatabase
    let contentErrorMessage: String?
    let hasUnsavedChanges: (String) -> Bool
    let openSite: () -> Void
    let createSite: () -> Void

    @State private var expandedTagNames: Set<String> = []
    @State private var expandedCategoryNames: Set<String> = []

    private let expandedSidebarMinWidth: CGFloat = 320

    private var tagGroups: [MetadataGroup] {
        metadataGroups(for: \.tags)
    }

    private var categoryGroups: [MetadataGroup] {
        metadataGroups(for: \.categories)
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
                    case .posts:
                        postsState
                    case .pages:
                        pagesState
                    case .publishing:
                        placeholderState
                    case .siteSettings:
                        siteSettingsState
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

    private var postsState: some View {
        VStack(alignment: .leading, spacing: 4) {
            postsBrowseModePicker
            sortOrderPicker

            if let contentErrorMessage {
                Text(contentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            postsList
        }
        .onChange(of: postBrowseMode) { _, newValue in
            expandInitialGroupsIfNeeded(for: newValue)
        }
        .onAppear {
            expandInitialGroupsIfNeeded(for: postBrowseMode)
        }
    }

    private var pagesState: some View {
        VStack(alignment: .leading, spacing: 4) {
            sortOrderPicker

            if let contentErrorMessage {
                Text(contentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            flatList(items: contentItems)
        }
    }

    private var postsBrowseModePicker: some View {
        HStack(spacing: 4) {
            ForEach(PostBrowseMode.allCases) { mode in
                Button {
                    postBrowseMode = mode
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(postBrowseMode == mode ? .primary : .secondary)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(postBrowseMode == mode ? Color.primary.opacity(0.12) : .clear)
                }
            }
        }
        .padding(4)
        .padding(.horizontal)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal)
    }

    private var sortOrderPicker: some View {
        Picker("Order", selection: $sortOrder) {
            ForEach(ContentSortOrder.allCases) { order in
                Text(order.title).tag(order)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var postsList: some View {
        switch postBrowseMode {
        case .date:
            flatList(items: contentItems)
        case .tags:
            groupedList(
                groups: tagGroups,
                expandedNames: $expandedTagNames,
                emptyTitle: "No Tags Found",
                emptyDescription: "Add tags in front matter to group posts here."
            )
        case .categories:
            groupedList(
                groups: categoryGroups,
                expandedNames: $expandedCategoryNames,
                emptyTitle: "No Categories Found",
                emptyDescription: "Add categories in front matter to group posts here."
            )
        }
    }

    private func flatList(items: [HugoContentItem]) -> some View {
        List(selection: $selectedPostID) {
            ForEach(items) { item in
                ContentSidebarRow(
                    item: item,
                    hasUnsavedChanges: hasUnsavedChanges(item.id)
                )
                .tag(item.id as String?)
            }
        }
        .listStyle(.inset)
    }

    private func groupedList(
        groups: [MetadataGroup],
        expandedNames: Binding<Set<String>>,
        emptyTitle: String,
        emptyDescription: String
    ) -> some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "folder.badge.questionmark",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedPostID) {
                    ForEach(groups) { group in
                        DisclosureGroup(
                            isExpanded: disclosureBinding(for: group.name, expandedNames: expandedNames)
                        ) {
                            ForEach(group.items) { item in
                                ContentSidebarRow(
                                    item: item,
                                    hasUnsavedChanges: hasUnsavedChanges(item.id)
                                )
                                .tag(item.id as String?)
                            }
                        } label: {
                            Label {
                                Text(group.name)
                            } icon: {
                                Image(systemName: "folder")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
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

    private var siteSettingsState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection("General") {
                    LabeledContent("Base URL") {
                        TextField("https://example.com/", text: $siteSettings.baseURL)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity)
                    }

                    LabeledContent("Language") {
                        TextField("en-us", text: $siteSettings.languageCode)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }

                    LabeledContent("Title") {
                        TextField("Site title", text: $siteSettings.title)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }

                    LabeledContent("Author") {
                        TextField("Author name", text: $siteSettings.author)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }

                    LabeledContent("Copyright") {
                        TextField("Copyright notice", text: $siteSettings.copyright)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }
                }

                settingsSection("Publishing") {
                    Toggle("Canonify URLs", isOn: $siteSettings.canonifyURLs)
                    Toggle("Generate robots.txt", isOn: $siteSettings.enableRobotsTXT)
                }

                if config != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Loaded From Config")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("Values are initialized from the site's current Hugo config when the site opens.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var collapsedSidebar: some View {
        EmptyView()
    }

    private func disclosureBinding(
        for name: String,
        expandedNames: Binding<Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: {
                expandedNames.wrappedValue.contains(name)
            },
            set: { isExpanded in
                if isExpanded {
                    expandedNames.wrappedValue.insert(name)
                } else {
                    expandedNames.wrappedValue.remove(name)
                }
            }
        )
    }

    private func metadataGroups(
        for keyPath: KeyPath<HugoContentMetadata, [String]>
    ) -> [MetadataGroup] {
        var groupedItems: [String: [HugoContentItem]] = [:]
        var displayNamesByNormalizedName: [String: String] = [:]

        for item in contentItems {
            guard let metadata = contentMetadataDatabase.metadata(for: item.id) else {
                continue
            }

            for value in metadata[keyPath: keyPath] {
                let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalizedValue.isEmpty else {
                    continue
                }

                groupedItems[normalizedValue, default: []].append(item)
                displayNamesByNormalizedName[normalizedValue] = displayNamesByNormalizedName[normalizedValue] ?? value
            }
        }

        return groupedItems.keys.sorted().compactMap { normalizedName in
            guard let items = groupedItems[normalizedName],
                  let displayName = displayNamesByNormalizedName[normalizedName] else {
                return nil
            }

            return MetadataGroup(name: displayName, items: items)
        }
    }

    private func expandInitialGroupsIfNeeded(for mode: PostBrowseMode) {
        switch mode {
        case .date:
            break
        case .tags:
            if expandedTagNames.isEmpty {
                expandedTagNames = Set(tagGroups.prefix(3).map(\.name))
            }
        case .categories:
            if expandedCategoryNames.isEmpty {
                expandedCategoryNames = Set(categoryGroups.prefix(3).map(\.name))
            }
        }
    }
}

private struct MetadataGroup: Identifiable {
    let name: String
    let items: [HugoContentItem]

    var id: String { name }
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
