import SwiftUI
import AppKit
import Foundation
import OSLog

struct ContentView: View {
    private static let sidebarWidthStorageKey = "ContentView.sidebarWidth"
    private static let editorWidthStorageKey = "ContentView.editorWidth"

    @EnvironmentObject private var sidebarNavigation: SidebarNavigationModel

    @AppStorage(EditorColorScheme.appStorageKey) private var editorColorSchemeID = EditorColorScheme.defaultPreset.id
    @AppStorage(PostDatePreferences.autoUpdateLastModifiedKey) private var autoUpdateLastModified = PostDatePreferences.autoUpdateLastModifiedDefault
    @AppStorage(HugoDateTimeFormat.appStorageKey) private var selectedDateTimeFormatID = HugoDateTimeFormat.defaultFormat.rawValue
    @AppStorage(Self.sidebarWidthStorageKey) private var storedSidebarWidth = 340.0
    @AppStorage(Self.editorWidthStorageKey) private var storedEditorWidth = 400.0
    @State private var showSidebar = true
    @State private var selectedPostID: String? = nil
    @State private var markdownText: String = ""
    @State private var siteIsOpen = false

    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var siteURL: URL? = nil
    @State private var hugoServerProcess: Process? = nil
    @State private var previewURL: URL? = nil
    @State private var config: HugoConfig? = nil
    @State private var contentItems: [HugoContentItem] = []
    @State private var contentMetadataDatabase = HugoContentMetadataDatabase()
    @State private var contentErrorMessage: String? = nil
    @State private var hugoServerStatus = HugoServerStatus(phase: .stopped, message: "No server running", serverURL: nil)
    @State private var savedContentByID: [String: String] = [:]
    @State private var draftContentByID: [String: String] = [:]
    @State private var siteSettings = SiteSettings()
    @State private var isSaving = false
    @State private var contentSortOrder: ContentSortOrder = .publishDateDescending
    @State private var postBrowseMode: PostBrowseMode = .date

    @State private var hugoStatus: HugoStatus = .checking
    @StateObject private var markdownEditorController = MarkdownEditorController()
    @State private var sidebarWidth: CGFloat = 340
    @State private var editorWidth: CGFloat = 400
    @State private var pendingSidebarWidth: CGFloat = 340
    @State private var pendingEditorWidth: CGFloat = 400
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var editorDragStartWidths: EditorDragStart?
    @State private var paneResizeTask: Task<Void, Never>?

    private var filteredContentItems: [HugoContentItem] {
        let tabFilteredItems: [HugoContentItem] = switch sidebarNavigation.selectedTab {
        case .posts:
            contentItems.filter { item in
                item.section.localizedCaseInsensitiveCompare("posts") == .orderedSame
            }
        case .pages:
            contentItems.filter { item in
                item.section.localizedCaseInsensitiveCompare("posts") != .orderedSame
            }
        case .publishing, .siteSettings:
            []
        }

        return tabFilteredItems.sorted(by: compareContentItems)
    }

    private var editorColorScheme: EditorColorScheme {
        EditorColorScheme.preset(withID: editorColorSchemeID)
    }

    private var selectedDateTimeFormat: HugoDateTimeFormat {
        HugoDateTimeFormat.from(appStorageValue: selectedDateTimeFormatID)
    }

    private var selectedContentItem: HugoContentItem? {
        guard let selectedPostID else {
            return nil
        }

        return contentItems.first(where: { $0.id == selectedPostID })
    }

    private let sidebarMinimumWidth: CGFloat = 280
    private let sidebarMaximumWidth: CGFloat = 420
    private let editorMinimumWidth: CGFloat = 320
    private let editorMaximumWidth: CGFloat = 720
    private let previewMinimumWidth: CGFloat = 360
    private let dividerWidth: CGFloat = 10
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                Group {
                    if siteIsOpen {
                        resizableWorkspace(totalWidth: proxy.size.width)
                            .disabled(hugoStatus != .compatible)
                    } else {
                        initialWorkspaceState
                    }
                }
            }
            Divider()
            serverStatusBar
        }
        .animation(.default, value: showSidebar)
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showSidebar.toggle()
                } label: {
                    Image(systemName: showSidebar ? "sidebar.left" : "sidebar.right")
                }
                .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")
            }

            ToolbarItemGroup(placement: .principal) {
                Button("Open", systemImage: "folder") {
                    openSite()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(hugoStatus != .compatible || isLoading)

                Button("Save", systemImage: "square.and.arrow.down") {
                    saveSelectedPost()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!canSaveSelectedPost)

                Button("Save All", systemImage: "square.and.arrow.down.on.square") {
                    saveAllPosts()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!canSaveAnyPosts)
            }
        }
        .onAppear {
            sidebarNavigation.isSiteOpen = siteIsOpen
            sidebarWidth = CGFloat(storedSidebarWidth)
            editorWidth = CGFloat(storedEditorWidth)
            pendingSidebarWidth = sidebarWidth
            pendingEditorWidth = editorWidth
        }
        .onDisappear {
            stopHugoServer(hugoServerProcess)
            hugoServerProcess = nil
            previewURL = nil
            hugoServerStatus = HugoServerStatus(phase: .stopped, message: "No server running", serverURL: nil)
            paneResizeTask?.cancel()
            commitPaneWidths()
        }
        .onChange(of: siteIsOpen) { _, newValue in
            sidebarNavigation.isSiteOpen = newValue
            if !newValue {
                sidebarNavigation.selectedTab = .posts
                postBrowseMode = .date
            }
        }
        .onChange(of: sidebarNavigation.selectedTab) { _, _ in
            syncSelectionWithVisibleTab()
        }
        .onChange(of: contentItems) { _, _ in
            syncSelectionWithVisibleTab()
        }
        .onChange(of: selectedPostID) { _, newValue in
            guard let newValue else {
                previewURL = previewURLForSelectedPost(using: hugoServerStatus.serverURL)
                markdownText = ""
                return
            }

            guard let siteURL,
                  let selectedItem = contentItems.first(where: { $0.id == newValue }) else {
                return
            }

            updatePreviewURL(for: selectedItem)

            Task {
                do {
                    let content = try await loadContentBodyAsync(from: siteURL, relativePath: selectedItem.path)
                    await MainActor.run {
                        savedContentByID[selectedItem.id] = content
                        let draftContent = draftContentByID[selectedItem.id] ?? content
                        draftContentByID[selectedItem.id] = draftContent
                        markdownText = draftContent
                        contentErrorMessage = nil
                    }
                } catch {
                    AppLogger.content.error("Failed to load content body for \(selectedItem.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        contentErrorMessage = "Failed to load content: \(error.localizedDescription)"
                    }
                }
            }
        }
        .onChange(of: markdownText) { _, newValue in
            guard let selectedPostID else {
                return
            }

            draftContentByID[selectedPostID] = newValue
        }
        .overlay {
            switch hugoStatus {
            case .checking:
                Color(.black)
                    .opacity(0.25)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView("Checking Hugo version...")
                            .font(.title2)
                            .padding()
                            .background(.thinMaterial)
                            .cornerRadius(10)
                    }
            case .notInstalled:
                Color(.black)
                    .opacity(0.25)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            Text("Hugo is not installed.\nPlease install Hugo before using this app.")
                                .multilineTextAlignment(.center)
                                .font(.title3)
                            Button("Quit") {
                                NSApp.terminate(nil)
                            }
                            .keyboardShortcut(.cancelAction)
                            .controlSize(.large)
                        }
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .frame(maxWidth: 400)
                    }
            case .incompatibleVersion(let found):
                Color(.black)
                    .opacity(0.25)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            Text("Hugo version \(found.versionString) is not supported.\nPlease install Hugo v0.158.0 or newer.")
                                .multilineTextAlignment(.center)
                                .font(.title3)
                            Button("Quit") {
                                NSApp.terminate(nil)
                            }
                            .keyboardShortcut(.cancelAction)
                            .controlSize(.large)
                        }
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .frame(maxWidth: 400)
                    }
            case .compatible:
                EmptyView()
            }
        }
        .task {
            do {
                let foundVersionOpt: HugoVersion? = try await checkHugoVersion()
                if let foundVersion = foundVersionOpt {
                    if foundVersion >= minimumHugoVersion {
                        AppLogger.app.notice("Hugo compatibility check passed with version \(foundVersion.versionString, privacy: .public)")
                        hugoStatus = .compatible
                    } else {
                        AppLogger.app.error("Hugo version \(foundVersion.versionString, privacy: .public) is below minimum \(minimumHugoVersion.versionString, privacy: .public)")
                        hugoStatus = .incompatibleVersion(found: foundVersion)
                    }
                } else {
                    AppLogger.app.error("Hugo compatibility check returned no version")
                    hugoStatus = .notInstalled
                }
            } catch {
                AppLogger.app.error("Hugo compatibility check failed: \(error.localizedDescription, privacy: .public)")
                hugoStatus = .notInstalled
            }
        }
    }

    @ViewBuilder
    private func resizableWorkspace(totalWidth: CGFloat) -> some View {
        let metrics = layoutMetrics(for: totalWidth)

        HStack(spacing: 0) {
            if showSidebar {
                sidebarPane
                    .frame(width: metrics.sidebarWidth)

                paneDivider(cursor: .resizeLeftRight) { value in
                    updateSidebarWidth(with: value.translation.width, totalWidth: totalWidth)
                } onEnded: {
                    sidebarDragStartWidth = nil
                    commitPaneWidths()
                }
            }

            Group {
                if selectedContentItem != nil {
                    editorPane
                } else {
                    editorPlaceholderPane
                }
            }
            .frame(width: metrics.editorWidth)

            paneDivider(cursor: .resizeLeftRight) { value in
                updateEditorWidth(with: value.translation.width, totalWidth: totalWidth)
            } onEnded: {
                editorDragStartWidths = nil
                commitPaneWidths()
            }

            previewPane
                .frame(minWidth: previewMinimumWidth, maxWidth: .infinity)
        }
    }

    private var sidebarPane: some View {
        ContentSidebar(
            isVisible: $showSidebar,
            isSiteOpen: $siteIsOpen,
            selectedPostID: $selectedPostID,
            selectedTab: $sidebarNavigation.selectedTab,
            sortOrder: $contentSortOrder,
            postBrowseMode: $postBrowseMode,
            siteSettings: $siteSettings,
            isLoading: isLoading,
            errorMessage: errorMessage,
            config: config,
            contentItems: filteredContentItems,
            contentMetadataDatabase: contentMetadataDatabase,
            contentErrorMessage: contentErrorMessage,
            hasUnsavedChanges: hasUnsavedChanges(for:),
            openSite: openSite,
            createSite: { siteIsOpen = true /* TODO: implement creation */ }
        )
    }

    private var editorPane: some View {
        VStack(alignment: .leading) {
            MarkdownEditorView(
                text: $markdownText,
                colorScheme: editorColorScheme,
                controller: markdownEditorController
            )
        }
    }

    private var editorPlaceholderPane: some View {
        ContentUnavailableView(
            "No Content Selected",
            systemImage: "square.and.pencil",
            description: Text("Select a post or page to edit it here.")
        )
        .frame(maxHeight: .infinity)
    }

    private var previewPane: some View {
        VStack(alignment: .leading) {
            Group {
                if let previewURL {
                    WebView(url: previewURL)
                } else {
                    ContentUnavailableView(
                        "Preview Unavailable",
                        systemImage: "network.slash",
                        description: Text(hugoServerStatus.message)
                    )
                }
            }
            .padding(8)
        }
    }

    private func paneDivider(
        cursor: NSCursor,
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: dividerWidth)
            .overlay {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(onChanged)
                    .onEnded { _ in
                        onEnded()
                    }
            )
    }
    
    private func openSite() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                AppLogger.app.notice("Opening Hugo site at \(url.path, privacy: .public)")
                DispatchQueue.main.async {
                    isLoading = true
                    errorMessage = nil
                }
                Task {
                    do {
                        let configResult = try await loadHugoConfigAsync(from: url)
                        let loadedContentItems = try await loadHugoContentListAsync(from: url)
                        let metadataDatabase = try await loadHugoContentMetadataDatabaseAsync(
                            from: url,
                            items: loadedContentItems
                        )
                        let serverProcess: Process?

                        if loadedContentItems.isEmpty {
                            AppLogger.server.notice("Skipping Hugo server start because no Hugo content items were found in \(url.path, privacy: .public)")
                            await MainActor.run {
                                previewURL = nil
                                hugoServerStatus = HugoServerStatus(phase: .stopped, message: "No Hugo content found", serverURL: nil)
                            }
                            serverProcess = nil
                        } else {
                            serverProcess = try startHugoServer(from: url) { status in
                                hugoServerStatus = status
                                if let serverURL = status.serverURL {
                                    previewURL = previewURLForSelectedPost(using: serverURL)
                                } else if status.phase == .stopped || status.phase == .failed {
                                    previewURL = nil
                                }
                            }
                        }

                        DispatchQueue.main.async {
                            stopHugoServer(hugoServerProcess)
                            config = configResult
                            siteSettings = SiteSettings(config: configResult)
                            contentItems = loadedContentItems
                            contentMetadataDatabase = metadataDatabase
                            siteURL = url
                            hugoServerProcess = serverProcess
                            previewURL = previewURLForSelectedPost(using: hugoServerStatus.serverURL)
                            siteIsOpen = true
                            isLoading = false
                            errorMessage = nil
                            contentErrorMessage = nil
                            savedContentByID = [:]
                            draftContentByID = [:]
                            markdownText = ""
                            isSaving = false
                            syncSelectionWithVisibleTab()
                        }
                    } catch {
                        AppLogger.app.error("Failed to load Hugo config for site at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        DispatchQueue.main.async {
                            stopHugoServer(hugoServerProcess)
                            hugoServerProcess = nil
                            errorMessage = "Failed to load Hugo site: \(error.localizedDescription)"
                            isLoading = false
                            config = nil
                            siteSettings = SiteSettings()
                            contentItems = []
                            contentMetadataDatabase = HugoContentMetadataDatabase()
                            selectedPostID = nil
                            siteURL = nil
                            siteIsOpen = false
                            previewURL = nil
                            hugoServerStatus = HugoServerStatus(phase: .failed, message: "Server unavailable", serverURL: nil)
                            contentErrorMessage = nil
                            savedContentByID = [:]
                            draftContentByID = [:]
                            markdownText = ""
                            isSaving = false
                        }
                    }
                }
            }
        }
    }

    private var serverStatusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(serverStatusColor)
                .frame(width: 9, height: 9)

            Text(serverStatusTitle)
                .font(.caption)
                .fontWeight(.semibold)

            Text(hugoServerStatus.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if let serverURL = hugoServerStatus.serverURL {
                Text(serverURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var initialWorkspaceState: some View {
        Group {
            if isLoading {
                ProgressView("Loading site...")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.title3)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                ContentUnavailableView(
                    "Open or create a site to start editing",
                    systemImage: "folder.badge.questionmark"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func updatePreviewURL(for item: HugoContentItem) {
        previewURL = previewURL(for: item, serverURL: hugoServerStatus.serverURL)
    }

    private func compareContentItems(_ lhs: HugoContentItem, _ rhs: HugoContentItem) -> Bool {
        let lhsDate = contentMetadataDatabase.metadata(for: lhs.id)?.publishDate
        let rhsDate = contentMetadataDatabase.metadata(for: rhs.id)?.publishDate

        if lhsDate != rhsDate {
            switch (lhsDate, rhsDate) {
            case let (lhsDate?, rhsDate?):
                switch contentSortOrder {
                case .publishDateDescending:
                    return lhsDate > rhsDate
                case .publishDateAscending:
                    return lhsDate < rhsDate
                }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }
        }

        let titleComparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    private func previewURLForSelectedPost(using serverURL: URL?) -> URL? {
        guard let selectedPostID,
              let selectedItem = contentItems.first(where: { $0.id == selectedPostID }) else {
            return serverURL
        }

        return previewURL(for: selectedItem, serverURL: serverURL)
    }

    private func previewURL(for item: HugoContentItem, serverURL: URL?) -> URL? {
        guard let serverURL else { return nil }

        if let permalinkURL = URL(string: item.permalink),
           let components = URLComponents(url: permalinkURL, resolvingAgainstBaseURL: false) {
            var serverComponents = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
            serverComponents?.path = components.path.isEmpty ? "/" : components.path
            serverComponents?.query = components.query
            serverComponents?.fragment = components.fragment
            return serverComponents?.url
        }

        if item.permalink.hasPrefix("/") {
            return serverURL.appending(path: String(item.permalink.dropFirst()))
        }

        return serverURL
    }

    private func layoutMetrics(for totalWidth: CGFloat) -> LayoutMetrics {
        let visibleSidebarWidth = showSidebar ? sidebarWidth : 0
        let availableWithoutPreview = totalWidth - previewMinimumWidth - dividerWidth
        let sidebarWidth = showSidebar
            ? min(max(visibleSidebarWidth, sidebarMinimumWidth), min(sidebarMaximumWidth, max(availableWithoutPreview - editorMinimumWidth - dividerWidth, sidebarMinimumWidth)))
            : 0

        let editorAvailable = totalWidth - sidebarWidth - previewMinimumWidth - dividerWidth - (showSidebar ? dividerWidth : 0)
        let editorWidth = min(
            max(self.editorWidth, editorMinimumWidth),
            min(editorMaximumWidth, max(editorAvailable, editorMinimumWidth))
        )

        return LayoutMetrics(sidebarWidth: sidebarWidth, editorWidth: editorWidth)
    }

    private func updateSidebarWidth(with translation: CGFloat, totalWidth: CGFloat) {
        guard showSidebar else {
            return
        }

        let startWidth = sidebarDragStartWidth ?? sidebarWidth
        if sidebarDragStartWidth == nil {
            sidebarDragStartWidth = startWidth
        }

        let maxWidth = maxSidebarWidth(for: totalWidth)
        pendingSidebarWidth = min(max(startWidth + translation, sidebarMinimumWidth), maxWidth)
        schedulePaneResizeRender()
    }

    private func updateEditorWidth(with translation: CGFloat, totalWidth: CGFloat) {
        if editorDragStartWidths == nil {
            editorDragStartWidths = EditorDragStart(
                sidebarWidth: showSidebar ? sidebarWidth : 0,
                editorWidth: editorWidth
            )
        }

        guard let editorDragStartWidths else {
            return
        }

        let maxWidth = maxEditorWidth(for: totalWidth, sidebarWidth: editorDragStartWidths.sidebarWidth)
        pendingEditorWidth = min(max(editorDragStartWidths.editorWidth + translation, editorMinimumWidth), maxWidth)
        schedulePaneResizeRender()
    }

    private func maxSidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        let maxAllowed = totalWidth - previewMinimumWidth - editorMinimumWidth - (dividerWidth * 2)
        return min(sidebarMaximumWidth, max(sidebarMinimumWidth, maxAllowed))
    }

    private func maxEditorWidth(for totalWidth: CGFloat, sidebarWidth: CGFloat) -> CGFloat {
        let dividerAllowance = showSidebar ? dividerWidth * 2 : dividerWidth
        let maxAllowed = totalWidth - sidebarWidth - previewMinimumWidth - dividerAllowance
        return min(editorMaximumWidth, max(editorMinimumWidth, maxAllowed))
    }

    private func commitPaneWidths() {
        paneResizeTask?.cancel()
        sidebarWidth = pendingSidebarWidth
        editorWidth = pendingEditorWidth
        storedSidebarWidth = Double(sidebarWidth)
        storedEditorWidth = Double(editorWidth)
    }

    private func schedulePaneResizeRender() {
        paneResizeTask?.cancel()
        paneResizeTask = Task {
            try? await Task.sleep(nanoseconds: 33_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                withAnimation(nil) {
                    sidebarWidth = pendingSidebarWidth
                    editorWidth = pendingEditorWidth
                }
            }
        }
    }

    private var canSaveSelectedPost: Bool {
        guard let selectedPostID, siteURL != nil else {
            return false
        }

        return hasUnsavedChanges(for: selectedPostID) && !isSaving
    }

    private var windowTitle: String {
        guard let title = config?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return "Oneka"
        }

        return title
    }

    private var canSaveAnyPosts: Bool {
        siteURL != nil && contentItems.contains(where: { hasUnsavedChanges(for: $0.id) }) && !isSaving
    }

    private func hasUnsavedChanges(for itemID: String) -> Bool {
        guard let savedContent = savedContentByID[itemID],
              let draftContent = draftContentByID[itemID] else {
            return false
        }

        return savedContent != draftContent
    }

    private func saveSelectedPost() {
        guard let selectedPostID,
              hasUnsavedChanges(for: selectedPostID) else {
            return
        }

        savePosts(withIDs: [selectedPostID])
    }

    private func saveAllPosts() {
        let itemIDsToSave = contentItems
            .map(\.id)
            .filter(hasUnsavedChanges(for:))

        guard !itemIDsToSave.isEmpty else {
            return
        }

        savePosts(withIDs: itemIDsToSave)
    }

    private func savePosts(withIDs itemIDs: [String]) {
        guard !isSaving, let siteURL else {
            return
        }

        let saveDate = Date()
        let selectedItemID = selectedPostID
        if autoUpdateLastModified,
           let selectedItemID,
           itemIDs.contains(selectedItemID),
           let selectedDraftContent = draftContentByID[selectedItemID],
           let selectedItem = contentItems.first(where: { $0.id == selectedItemID }),
           hasUnsavedChanges(for: selectedItemID) {
            let updatedContent = updatingLastModifiedDate(
                in: selectedDraftContent,
                to: saveDate,
                format: selectedDateTimeFormat
            )

            if updatedContent != selectedDraftContent,
               markdownEditorController.replaceTextUsingUndo(updatedContent, colorScheme: editorColorScheme) {
                draftContentByID[selectedItemID] = updatedContent
                markdownText = updatedContent
                AppLogger.content.notice("Updated lastmod in editor before saving \(selectedItem.path, privacy: .public)")
            }
        }

        let pendingSaves = itemIDs.compactMap { itemID -> PendingSave? in
            guard let item = contentItems.first(where: { $0.id == itemID }),
                  let draftContent = draftContentByID[itemID],
                  hasUnsavedChanges(for: itemID) else {
                return nil
            }

            let contentToWrite = autoUpdateLastModified
                ? updatingLastModifiedDate(in: draftContent, to: saveDate, format: selectedDateTimeFormat)
                : draftContent

            return PendingSave(itemID: itemID, item: item, contentToWrite: contentToWrite)
        }

        guard !pendingSaves.isEmpty else {
            return
        }

        isSaving = true
        contentErrorMessage = nil

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    for pendingSave in pendingSaves {
                        let fileURL = siteURL.appendingPathComponent(pendingSave.item.path)
                        try pendingSave.contentToWrite.write(to: fileURL, atomically: true, encoding: .utf8)
                    }
                }.value

                for pendingSave in pendingSaves {
                    AppLogger.content.notice("Saved content to \(pendingSave.item.path, privacy: .public)")
                }

                await MainActor.run {
                    for pendingSave in pendingSaves {
                        savedContentByID[pendingSave.itemID] = pendingSave.contentToWrite
                        draftContentByID[pendingSave.itemID] = pendingSave.contentToWrite
                        if pendingSave.itemID == selectedPostID {
                            markdownText = pendingSave.contentToWrite
                        }
                    }
                    isSaving = false
                }
            } catch {
                AppLogger.content.error("Failed to save content: \(error.localizedDescription, privacy: .public)")

                await MainActor.run {
                    contentErrorMessage = "Failed to save content: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }

    private func syncSelectionWithVisibleTab() {
        let visibleIDs = Set(filteredContentItems.map(\.id))

        guard sidebarNavigation.selectedTab == .posts || sidebarNavigation.selectedTab == .pages else {
            selectedPostID = nil
            markdownText = ""
            return
        }

        guard !filteredContentItems.isEmpty else {
            selectedPostID = nil
            markdownText = ""
            return
        }

        if let selectedPostID, visibleIDs.contains(selectedPostID) {
            return
        }

        selectedPostID = filteredContentItems.first?.id
    }

    private var serverStatusTitle: String {
        switch hugoServerStatus.phase {
        case .stopped:
            "Stopped"
        case .starting:
            "Starting"
        case .building:
            "Building"
        case .serving:
            "Serving"
        case .warning:
            "Warning"
        case .failed:
            "Failed"
        }
    }

    private var serverStatusColor: Color {
        switch hugoServerStatus.phase {
        case .stopped:
            .secondary
        case .starting, .building:
            .orange
        case .serving:
            .green
        case .warning:
            .yellow
        case .failed:
            .red
        }
    }
}

private struct PendingSave {
    let itemID: String
    let item: HugoContentItem
    let contentToWrite: String
}

private struct LayoutMetrics {
    let sidebarWidth: CGFloat
    let editorWidth: CGFloat
}

private struct EditorDragStart {
    let sidebarWidth: CGFloat
    let editorWidth: CGFloat
}

// NOTE: You will need to implement the WebView struct that wraps WKWebView for SwiftUI.
// See next steps for adding this.

#Preview {
    ContentView()
}
