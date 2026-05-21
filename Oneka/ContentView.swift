import SwiftUI
import AppKit
import Foundation
import OSLog
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    private static let sidebarWidthStorageKey = "ContentView.sidebarWidth"
    private static let editorWidthStorageKey = "ContentView.editorWidth"
    private static let lastOpenedSitePathStorageKey = "ContentView.lastOpenedSitePath"
    private static let lastSiteBrowserDirectoryPathStorageKey = "ContentView.lastSiteBrowserDirectoryPath"
    private static let lastImageBrowserDirectoryPathStorageKey = "ContentView.lastImageBrowserDirectoryPath"

    @EnvironmentObject private var sidebarNavigation: SidebarNavigationModel

    @AppStorage(EditorColorScheme.appStorageKey) private var editorColorSchemeID = EditorColorScheme.defaultPreset.id
    @AppStorage(PostDatePreferences.autoUpdateLastModifiedKey) private var autoUpdateLastModified = PostDatePreferences.autoUpdateLastModifiedDefault
    @AppStorage(HugoDateTimeFormat.appStorageKey) private var selectedDateTimeFormatID = HugoDateTimeFormat.defaultFormat.rawValue
    @AppStorage(Self.sidebarWidthStorageKey) private var storedSidebarWidth = 340.0
    @AppStorage(Self.editorWidthStorageKey) private var storedEditorWidth = 400.0
    @AppStorage(Self.lastOpenedSitePathStorageKey) private var lastOpenedSitePath = ""
    @AppStorage(Self.lastSiteBrowserDirectoryPathStorageKey) private var lastSiteBrowserDirectoryPath = ""
    @AppStorage(Self.lastImageBrowserDirectoryPathStorageKey) private var lastImageBrowserDirectoryPath = ""
    @State private var showSidebar = true
    @State private var showPreview = true
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
    @State private var isShowingImageImportPopover = false
    @State private var pendingImageInsertionKind: ImageInsertionKind = .image
    @State private var isShowingInternalLinkSheet = false
    @State private var isShowingImageFileImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageImportStatus: ImageImportStatus?
    @State private var pendingImageImport: PendingImageImport?
    @State private var pendingImageName = ""

    @State private var hugoStatus: HugoStatus = .checking
    @State private var hasAttemptedSiteRestore = false
    @StateObject private var markdownEditorController = MarkdownEditorController()
    @State private var sidebarWidth: CGFloat = 340
    @State private var editorWidth: CGFloat = 400
    @State private var pendingSidebarWidth: CGFloat = 340
    @State private var pendingEditorWidth: CGFloat = 400
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var editorDragStartWidths: EditorDragStart?
    @State private var hoveredDivider: PaneDividerKind?
    @State private var activeDivider: PaneDividerKind?

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

    private var lastSiteBrowserDirectoryURL: URL? {
        directoryURL(fromStoredPath: lastSiteBrowserDirectoryPath)
    }

    private var lastImageBrowserDirectoryURL: URL? {
        directoryURL(fromStoredPath: lastImageBrowserDirectoryPath)
    }

    private var selectedContentItem: HugoContentItem? {
        guard let selectedPostID else {
            return nil
        }

        return contentItems.first(where: { $0.id == selectedPostID })
    }

    private var linkableContentItems: [HugoContentItem] {
        contentItems.sorted(by: compareContentItems)
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
        .animation(.default, value: showPreview)
        .navigationTitle(windowTitle)
        .toolbar {
            contentToolbar
        }
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
        .onChange(of: siteIsOpen, handleSiteIsOpenChange)
        .onChange(of: sidebarNavigation.selectedTab) { _, _ in
            syncSelectionWithVisibleTab()
        }
        .onChange(of: contentItems) { _, _ in
            syncSelectionWithVisibleTab()
        }
        .onChange(of: selectedPostID, handleSelectedPostIDChange)
        .onChange(of: markdownText, handleMarkdownTextChange)
        .onReceive(NotificationCenter.default.publisher(for: .onekaOpenSiteRequested), perform: handleOpenSiteRequest)
        .onReceive(NotificationCenter.default.publisher(for: .onekaInsertImageRequested), perform: handleInsertImageRequest)
        .onReceive(NotificationCenter.default.publisher(for: .onekaInsertInternalLinkRequested), perform: handleInsertInternalLinkRequest)
        .onReceive(NotificationCenter.default.publisher(for: .onekaInsertDetailsShortcodeRequested), perform: handleInsertDetailsShortcodeRequest)
        .onReceive(NotificationCenter.default.publisher(for: .onekaInsertHighlightShortcodeRequested), perform: handleInsertHighlightShortcodeRequest)
        .onReceive(NotificationCenter.default.publisher(for: .onekaInsertInstagramShortcodeRequested), perform: handleInsertInstagramShortcodeRequest)
        .onReceive(NotificationCenter.default.publisher(for: .onekaInsertParamShortcodeRequested), perform: handleInsertParamShortcodeRequest)
        .onReceive(NotificationCenter.default.publisher(for: .onekaInsertQRShortcodeRequested), perform: handleInsertQRShortcodeRequest)
        .onReceive(NotificationCenter.default.publisher(for: .onekaInsertFigureRequested), perform: handleInsertFigureRequest)
        .onChange(of: canInsertImage, handleCanInsertImageChange)
        .onChange(of: canInsertInternalLink, handleCanInsertInternalLinkChange)
        .onChange(of: canInsertShortcode, handleCanInsertShortcodeChange)
        .onChange(of: selectedPhotoItem, handleSelectedPhotoItemChange)
        .fileImporter(
            isPresented: $isShowingImageFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            importImageFile(result)
        }
        .fileDialogMessage("Import an image into this Hugo site.")
        .fileDialogConfirmationLabel("Import")
        .fileDialogDefaultDirectory(lastImageBrowserDirectoryURL)
        .popover(isPresented: $isShowingImageImportPopover, arrowEdge: .top) {
            imageImportSourcePopover
        }
        .sheet(isPresented: $isShowingInternalLinkSheet) {
            internalLinkSheet
        }
        .sheet(item: $pendingImageImport) { pendingImport in
            imageImportNameSheet(for: pendingImport)
        }
        .overlay {
            hugoCompatibilityOverlay
        }
        .overlay {
            imageImportStatusOverlay
        }
        .task {
            await checkHugoCompatibility()
        }
    }

    private func handleAppear() {
        sidebarNavigation.isSiteOpen = siteIsOpen
        sidebarNavigation.canInsertImage = canInsertImage
        sidebarNavigation.canInsertInternalLink = canInsertInternalLink
        sidebarNavigation.canInsertShortcode = canInsertShortcode
        sidebarWidth = CGFloat(storedSidebarWidth)
        editorWidth = CGFloat(storedEditorWidth)
        pendingSidebarWidth = sidebarWidth
        pendingEditorWidth = editorWidth
    }

    private func handleDisappear() {
        sidebarNavigation.canInsertImage = false
        sidebarNavigation.canInsertInternalLink = false
        sidebarNavigation.canInsertShortcode = false
        stopHugoServer(hugoServerProcess)
        hugoServerProcess = nil
        previewURL = nil
        hugoServerStatus = HugoServerStatus(phase: .stopped, message: "No server running", serverURL: nil)
        commitPaneWidths()
    }

    private func handleSiteIsOpenChange(_ oldValue: Bool, _ newValue: Bool) {
        sidebarNavigation.isSiteOpen = newValue
        if !newValue {
            sidebarNavigation.selectedTab = .posts
            postBrowseMode = .date
        }
    }

    private func handleSelectedPostIDChange(_ oldValue: String?, _ newValue: String?) {
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

    private func handleMarkdownTextChange(_ oldValue: String, _ newValue: String) {
        guard let selectedPostID else {
            return
        }

        draftContentByID[selectedPostID] = newValue
    }

    private func handleSelectedPhotoItemChange(_ oldValue: PhotosPickerItem?, _ newValue: PhotosPickerItem?) {
        guard let newValue else {
            return
        }

        isShowingImageImportPopover = false
        importPhotoItem(newValue)
    }

    private func handleOpenSiteRequest(_ notification: Notification) {
        guard hugoStatus == .compatible, !isLoading else {
            return
        }

        openSite()
    }

    private func handleInsertImageRequest(_ notification: Notification) {
        showImageImportPopover(kind: .image)
    }

    private func handleInsertInternalLinkRequest(_ notification: Notification) {
        showInternalLinkSheet()
    }

    private func handleInsertDetailsShortcodeRequest(_ notification: Notification) {
        insertDetailsShortcode()
    }

    private func handleInsertHighlightShortcodeRequest(_ notification: Notification) {
        insertHighlightShortcode()
    }

    private func handleInsertInstagramShortcodeRequest(_ notification: Notification) {
        insertInstagramShortcode()
    }

    private func handleInsertParamShortcodeRequest(_ notification: Notification) {
        insertParamShortcode()
    }

    private func handleInsertQRShortcodeRequest(_ notification: Notification) {
        insertQRShortcode()
    }

    private func handleInsertFigureRequest(_ notification: Notification) {
        showImageImportPopover(kind: .figure)
    }

    private func handleCanInsertImageChange(_ oldValue: Bool, _ newValue: Bool) {
        sidebarNavigation.canInsertImage = newValue
        if !newValue {
            isShowingImageImportPopover = false
        }
    }

    private func handleCanInsertInternalLinkChange(_ oldValue: Bool, _ newValue: Bool) {
        sidebarNavigation.canInsertInternalLink = newValue
        if !newValue {
            isShowingInternalLinkSheet = false
        }
    }

    private func handleCanInsertShortcodeChange(_ oldValue: Bool, _ newValue: Bool) {
        sidebarNavigation.canInsertShortcode = newValue
    }

    @ToolbarContentBuilder
    private var contentToolbar: some ToolbarContent {
        if siteIsOpen {
            ToolbarItem(placement: .navigation) {
                Button {
                    showSidebar.toggle()
                } label: {
                    Label(showSidebar ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left")
                }
                .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")
            }
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

        if siteIsOpen {
            ToolbarItemGroup(placement: .primaryAction) {
                insertionToolbarButtons
                previewToolbarButton
            }
        }
    }

    private func checkHugoCompatibility() async {
        do {
            let foundVersionOpt: HugoVersion? = try await checkHugoVersion()
            if let foundVersion = foundVersionOpt {
                if foundVersion >= minimumHugoVersion {
                    AppLogger.app.notice("Hugo compatibility check passed with version \(foundVersion.versionString, privacy: .public)")
                    hugoStatus = .compatible
                    restoreLastOpenedSiteIfNeeded()
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

    private func restoreLastOpenedSiteIfNeeded() {
        guard !hasAttemptedSiteRestore, !lastOpenedSitePath.isEmpty else {
            return
        }

        hasAttemptedSiteRestore = true
        let url = URL(fileURLWithPath: lastOpenedSitePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        openSite(at: url, rememberLocation: false)
    }

    private func directoryURL(fromStoredPath path: String) -> URL? {
        guard !path.isEmpty else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    @ViewBuilder
    private func resizableWorkspace(totalWidth: CGFloat) -> some View {
        let metrics = layoutMetrics(for: totalWidth)

        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if showSidebar {
                    sidebarPane
                        .frame(width: metrics.sidebarWidth)

                    paneDivider(.sidebar, cursor: .resizeLeftRight) { value in
                        updateSidebarWidth(with: value.translation.width, totalWidth: totalWidth)
                    } onEnded: {
                        sidebarDragStartWidth = nil
                        activeDivider = nil
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
                .frame(width: showPreview ? metrics.editorWidth : nil)
                .frame(maxWidth: showPreview ? nil : .infinity)

                if showPreview {
                    paneDivider(.editor, cursor: .resizeLeftRight) { value in
                        updateEditorWidth(with: value.translation.width, totalWidth: totalWidth)
                    } onEnded: {
                        editorDragStartWidths = nil
                        activeDivider = nil
                        commitPaneWidths()
                    }

                    previewPane
                        .frame(minWidth: previewMinimumWidth, maxWidth: .infinity)
                }
            }

            paneDividerFeedbackOverlay(totalWidth: totalWidth, metrics: metrics)
        }
    }

    private var insertionToolbarButtons: some View {
        Group {
            Button {
                showInternalLinkSheet()
            } label: {
                Label("Insert Link", systemImage: "link")
            }
            .help("Insert a link to another page or post")
            .disabled(!canInsertInternalLink)

            Button {
                insertDetailsShortcode()
            } label: {
                Label("Insert Details", systemImage: "text.badge.plus")
            }
            .help("Insert a details shortcode")
            .disabled(!canInsertShortcode)

            Button {
                insertHighlightShortcode()
            } label: {
                Label("Insert Highlight", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .help("Insert a highlight shortcode")
            .disabled(!canInsertShortcode)

            Button {
                insertInstagramShortcode()
            } label: {
                Label("Insert Instagram", systemImage: "camera")
            }
            .help("Insert an Instagram shortcode")
            .disabled(!canInsertShortcode)

            Button {
                insertParamShortcode()
            } label: {
                Label("Insert Param", systemImage: "curlybraces")
            }
            .help("Insert a param shortcode")
            .disabled(!canInsertShortcode)

            Button {
                insertQRShortcode()
            } label: {
                Label("Insert QR", systemImage: "qrcode")
            }
            .help("Insert a QR shortcode")
            .disabled(!canInsertShortcode)

            Button {
                showImageImportPopover(kind: .figure)
            } label: {
                Label("Insert Figure", systemImage: "photo.on.rectangle")
            }
            .help("Import an image and insert a figure shortcode")
            .disabled(!canInsertImage)

            Button {
                showImageImportPopover(kind: .image)
            } label: {
                Label("Insert Image", systemImage: "photo.badge.plus")
            }
            .help("Import an image into this site")
            .disabled(!canInsertImage)
        }
    }

    private var previewToolbarButton: some View {
        Button {
            showPreview.toggle()
        } label: {
            Label(showPreview ? "Hide Preview" : "Show Preview", systemImage: "sidebar.right")
        }
        .help(showPreview ? "Hide Preview" : "Show Preview")
    }

    @ViewBuilder
    private var hugoCompatibilityOverlay: some View {
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
            hugoStatusWarningOverlay(message: "Hugo is not installed.\nPlease install Hugo before using this app.")
        case .incompatibleVersion(let found):
            hugoStatusWarningOverlay(message: "Hugo version \(found.versionString) is not supported.\nPlease install Hugo v0.158.0 or newer.")
        case .compatible:
            EmptyView()
        }
    }

    private func hugoStatusWarningOverlay(message: String) -> some View {
        Color(.black)
            .opacity(0.25)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text(message)
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
    }

    @ViewBuilder
    private var imageImportStatusOverlay: some View {
        if let imageImportStatus {
            Color.black
                .opacity(0.18)
                .ignoresSafeArea()
                .overlay {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(value: imageImportStatus.fractionCompleted)
                        Text(imageImportStatus.message)
                            .font(.headline)
                        Text("Importing image into this Hugo site")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(width: 320, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
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

    private var imageImportSourcePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pendingImageInsertionKind.importTitle)
                .font(.headline)

            Text("Selected images are copied into this Hugo site as web-ready JPEGs.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(imageImportStatus != nil)

            Button {
                isShowingImageImportPopover = false
                isShowingImageFileImporter = true
            } label: {
                Label("Import from File...", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(imageImportStatus != nil)
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }

    private func imageImportNameSheet(for pendingImport: PendingImageImport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name Imported Image")
                .font(.headline)

            Text("Oneka will save this image as a JPEG in your Hugo site.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Image name", text: $pendingImageName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    pendingImageImport = nil
                    pendingImageName = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("Import") {
                    let name = pendingImageName.trimmingCharacters(in: .whitespacesAndNewlines)
                    pendingImageImport = nil
                    pendingImageName = ""
                    importImage(
                        from: pendingImport.source,
                        preferredFilenameBase: name.isEmpty ? pendingImport.defaultName : name,
                        insertionKind: pendingImport.insertionKind
                    )
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
    }

    private var internalLinkSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Insert Internal Link")
                    .font(.headline)

                Spacer()

                Button("Cancel", role: .cancel) {
                    isShowingInternalLinkSheet = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            List(linkableContentItems) { item in
                Button {
                    insertInternalLink(to: item)
                } label: {
                    InternalLinkRow(item: item)
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 360)
        }
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private func paneDividerFeedbackOverlay(totalWidth: CGFloat, metrics: LayoutMetrics) -> some View {
        if let feedback = dividerFeedback(for: totalWidth, metrics: metrics) {
            ZStack(alignment: .topLeading) {
                paneGuide(at: feedback.minimumX, emphasized: false)
                paneGuide(at: feedback.maximumX, emphasized: false)

                if let currentX = feedback.currentX {
                    paneGuide(at: currentX, emphasized: true)
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func paneGuide(at x: CGFloat, emphasized: Bool) -> some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: proxy.size.height))
            }
            .stroke(
                emphasized ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.3),
                style: StrokeStyle(lineWidth: emphasized ? 2 : 1, dash: emphasized ? [] : [5, 5])
            )
        }
    }

    private func paneDivider(
        _ kind: PaneDividerKind,
        cursor: NSCursor,
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        Rectangle()
            .fill(dividerFill(for: kind))
            .frame(width: dividerWidth)
            .overlay {
                Rectangle()
                    .fill(dividerStroke(for: kind))
                    .frame(width: isDividerHighlighted(kind) ? 2 : 1)
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    hoveredDivider = kind
                } else if hoveredDivider == kind {
                    hoveredDivider = nil
                }

                if isHovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        activeDivider = kind
                        onChanged(value)
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
    }

    private func dividerFill(for kind: PaneDividerKind) -> Color {
        isDividerHighlighted(kind) ? Color.accentColor.opacity(0.12) : .clear
    }

    private func dividerStroke(for kind: PaneDividerKind) -> Color {
        isDividerHighlighted(kind) ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.12)
    }

    private func isDividerHighlighted(_ kind: PaneDividerKind) -> Bool {
        activeDivider == kind || hoveredDivider == kind
    }
    
    private func openSite() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.directoryURL = lastSiteBrowserDirectoryURL
        panel.begin { response in
            if response == .OK, let url = panel.url {
                openSite(at: url, rememberLocation: true)
            }
        }
    }

    private func openSite(at url: URL, rememberLocation: Bool) {
        AppLogger.app.notice("Opening Hugo site at \(url.path, privacy: .public)")
        isLoading = true
        errorMessage = nil

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

                await MainActor.run {
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
                    lastOpenedSitePath = url.path
                    if rememberLocation {
                        lastSiteBrowserDirectoryPath = url.deletingLastPathComponent().path
                    }
                    syncSelectionWithVisibleTab()
                }
            } catch {
                AppLogger.app.error("Failed to load Hugo config for site at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
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
        guard showPreview else {
            let sidebarWidth = showSidebar
                ? min(max(self.sidebarWidth, sidebarMinimumWidth), maxSidebarWidth(for: totalWidth))
                : 0

            return LayoutMetrics(sidebarWidth: sidebarWidth, editorWidth: totalWidth - sidebarWidth)
        }

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

    private func dividerFeedback(for totalWidth: CGFloat, metrics: LayoutMetrics) -> DividerFeedback? {
        let visibleDivider = activeDivider ?? hoveredDivider

        switch visibleDivider {
        case .sidebar:
            guard showSidebar else {
                return nil
            }

            let currentX = activeDivider == .sidebar
                ? pendingSidebarWidth + (dividerWidth / 2)
                : nil
            return DividerFeedback(
                currentX: currentX,
                minimumX: sidebarMinimumWidth + (dividerWidth / 2),
                maximumX: maxSidebarWidth(for: totalWidth) + (dividerWidth / 2)
            )
        case .editor:
            guard showPreview else {
                return nil
            }

            let leadingX = showSidebar ? metrics.sidebarWidth + dividerWidth : 0
            let currentX = activeDivider == .editor
                ? leadingX + pendingEditorWidth + (dividerWidth / 2)
                : nil
            return DividerFeedback(
                currentX: currentX,
                minimumX: leadingX + editorMinimumWidth + (dividerWidth / 2),
                maximumX: leadingX + maxEditorWidth(for: totalWidth, sidebarWidth: metrics.sidebarWidth) + (dividerWidth / 2)
            )
        case nil:
            return nil
        }
    }

    private func commitPaneWidths() {
        sidebarWidth = pendingSidebarWidth
        editorWidth = pendingEditorWidth
        storedSidebarWidth = Double(sidebarWidth)
        storedEditorWidth = Double(editorWidth)
    }

    private var canSaveSelectedPost: Bool {
        guard let selectedPostID, siteURL != nil else {
            return false
        }

        return hasUnsavedChanges(for: selectedPostID) && !isSaving
    }

    private var canInsertImage: Bool {
        siteURL != nil && selectedContentItem != nil && imageImportStatus == nil
    }

    private var canInsertInternalLink: Bool {
        siteURL != nil && selectedContentItem != nil && !contentItems.isEmpty
    }

    private var canInsertShortcode: Bool {
        siteURL != nil && selectedContentItem != nil
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

    private func showImageImportPopover(kind: ImageInsertionKind) {
        guard canInsertImage else {
            return
        }

        pendingImageInsertionKind = kind
        isShowingImageImportPopover = true
    }

    private func showInternalLinkSheet() {
        guard canInsertInternalLink else {
            return
        }

        isShowingInternalLinkSheet = true
    }

    private func insertDetailsShortcode() {
        guard canInsertShortcode else {
            return
        }

        if markdownEditorController.insertDetailsShortcode(colorScheme: editorColorScheme) {
            syncCurrentEditorTextToSelectedDraft()
        } else {
            let shortcode = "{{< details summary=\"Summary\" >}}\nAdd the details here.\n{{< /details >}}"
            markdownText += markdownText.isEmpty ? shortcode : "\n\n\(shortcode)"
            syncCurrentMarkdownTextToSelectedDraft()
        }
    }

    private func insertHighlightShortcode() {
        guard canInsertShortcode else {
            return
        }

        if markdownEditorController.insertHighlightShortcode(colorScheme: editorColorScheme) {
            syncCurrentEditorTextToSelectedDraft()
        } else {
            let shortcode = "{{< highlight text >}}\nAdd code here.\n{{< /highlight >}}"
            markdownText += markdownText.isEmpty ? shortcode : "\n\n\(shortcode)"
            syncCurrentMarkdownTextToSelectedDraft()
        }
    }

    private func insertInstagramShortcode() {
        guard canInsertShortcode else {
            return
        }

        if markdownEditorController.insertInstagramShortcode(colorScheme: editorColorScheme) {
            syncCurrentEditorTextToSelectedDraft()
        } else {
            let shortcode = "{{< instagram INSTAGRAM_POST_ID >}}"
            markdownText += markdownText.isEmpty ? shortcode : "\n\n\(shortcode)"
            syncCurrentMarkdownTextToSelectedDraft()
        }
    }

    private func insertParamShortcode() {
        guard canInsertShortcode else {
            return
        }

        if markdownEditorController.insertParamShortcode(colorScheme: editorColorScheme) {
            syncCurrentEditorTextToSelectedDraft()
        } else {
            let shortcode = "{{% param \"parameter_name\" %}}"
            markdownText += shortcode
            syncCurrentMarkdownTextToSelectedDraft()
        }
    }

    private func insertQRShortcode() {
        guard canInsertShortcode else {
            return
        }

        if markdownEditorController.insertQRShortcode(colorScheme: editorColorScheme) {
            syncCurrentEditorTextToSelectedDraft()
        } else {
            let shortcode = "{{< qr >}}\nhttps://example.com\n{{< /qr >}}"
            markdownText += markdownText.isEmpty ? shortcode : "\n\n\(shortcode)"
            syncCurrentMarkdownTextToSelectedDraft()
        }
    }

    private func insertInternalLink(to item: HugoContentItem) {
        let shortcode = internalLinkShortcode(for: item)
        if markdownEditorController.insertMarkdownLink(
            title: item.displayTitle,
            path: shortcode,
            colorScheme: editorColorScheme
        ) {
            syncCurrentEditorTextToSelectedDraft()
        } else {
            let markdown = "[\(escapedMarkdownLinkText(item.displayTitle))](\(shortcode))"
            markdownText += markdownText.isEmpty ? markdown : markdown
            syncCurrentMarkdownTextToSelectedDraft()
        }

        isShowingInternalLinkSheet = false
    }

    private func internalLinkShortcode(for item: HugoContentItem) -> String {
        "{{< ref \"\(escapedShortcodeArgument(refTargetPath(for: item)))\" >}}"
    }

    private func refTargetPath(for item: HugoContentItem) -> String {
        let normalizedPath = item.path.replacingOccurrences(of: "\\", with: "/")
        if normalizedPath.hasPrefix("content/") {
            return String(normalizedPath.dropFirst("content/".count))
        }

        return normalizedPath
    }

    private func escapedShortcodeArgument(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func escapedMarkdownLinkText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func importImageFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }
            lastImageBrowserDirectoryPath = url.deletingLastPathComponent().path
            prepareImageImport(
                source: .file(url),
                defaultName: ImageImportNaming.defaultName(forFileURL: url),
                insertionKind: pendingImageInsertionKind
            )
        case .failure(let error):
            contentErrorMessage = "Failed to import image: \(error.localizedDescription)"
        }
    }

    private func importPhotoItem(_ item: PhotosPickerItem) {
        Task {
            do {
                await MainActor.run {
                    imageImportStatus = ImageImportStatus(message: "Loading photo...", fractionCompleted: 0.05)
                }

                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ImageAssetImportError.unsupportedImage
                }
                let defaultName = ImageImportNaming.defaultName(
                    forImageData: data,
                    fallbackDate: nil
                )

                await MainActor.run {
                    selectedPhotoItem = nil
                    imageImportStatus = nil
                    prepareImageImport(
                        source: .data(data, suggestedFilename: "photo.jpg"),
                        defaultName: defaultName,
                        insertionKind: pendingImageInsertionKind
                    )
                }
            } catch {
                await MainActor.run {
                    selectedPhotoItem = nil
                    imageImportStatus = nil
                    contentErrorMessage = "Failed to import image: \(error.localizedDescription)"
                }
            }
        }
    }

    private func prepareImageImport(source: ImageImportSource, defaultName: String, insertionKind: ImageInsertionKind) {
        pendingImageName = defaultName
        pendingImageImport = PendingImageImport(source: source, defaultName: defaultName, insertionKind: insertionKind)
    }

    private func importImage(from source: ImageImportSource, preferredFilenameBase: String, insertionKind: ImageInsertionKind) {
        guard let siteURL, let selectedContentItem else {
            return
        }

        imageImportStatus = ImageImportStatus(message: "Preparing import...", fractionCompleted: 0.0)
        contentErrorMessage = nil

        Task {
            do {
                let importer = ImageAssetImporter()
                let importedAsset = try await importer.importImage(
                    from: source,
                    into: siteURL,
                    for: selectedContentItem,
                    siteBasePath: config?.baseURL,
                    preferredFilenameBase: preferredFilenameBase
                ) { status in
                    Task { @MainActor in
                        imageImportStatus = status
                    }
                }

                await MainActor.run {
                    insertImportedImageAsset(importedAsset, insertionKind: insertionKind)
                    imageImportStatus = nil
                    saveSelectedPost()
                    AppLogger.content.notice("Imported image to \(importedAsset.fileURL.path, privacy: .public)")
                }
            } catch {
                await MainActor.run {
                    imageImportStatus = nil
                    contentErrorMessage = "Failed to import image: \(error.localizedDescription)"
                }
            }
        }
    }

    private func insertImportedImageAsset(_ asset: ImportedImageAsset, insertionKind: ImageInsertionKind) {
        switch insertionKind {
        case .image:
            insertImportedImageMarkdown(asset)
        case .figure:
            insertImportedFigureShortcode(asset)
        }
    }

    private func insertImportedImageMarkdown(_ asset: ImportedImageAsset) {
        if markdownEditorController.insertMarkdownImage(
            altText: asset.altText,
            path: asset.markdownPath,
            colorScheme: editorColorScheme
        ) {
            syncCurrentEditorTextToSelectedDraft()
            return
        }

        let markdown = "![\(asset.altText)](\(asset.markdownPath))"
        markdownText += markdownText.isEmpty ? markdown : "\n\n\(markdown)"
        syncCurrentMarkdownTextToSelectedDraft()
    }

    private func insertImportedFigureShortcode(_ asset: ImportedImageAsset) {
        if markdownEditorController.insertFigureShortcode(
            src: asset.markdownPath,
            altText: asset.altText,
            colorScheme: editorColorScheme
        ) {
            syncCurrentEditorTextToSelectedDraft()
            return
        }

        let shortcode = "{{< figure\n  src=\"\(escapedShortcodeArgument(asset.markdownPath))\"\n  alt=\"\(escapedShortcodeArgument(asset.altText))\"\n  caption=\"Add a caption.\"\n>}}"
        markdownText += markdownText.isEmpty ? shortcode : "\n\n\(shortcode)"
        syncCurrentMarkdownTextToSelectedDraft()
    }

    private func syncCurrentEditorTextToSelectedDraft() {
        guard let text = markdownEditorController.currentText else {
            syncCurrentMarkdownTextToSelectedDraft()
            return
        }

        markdownText = text
        syncCurrentMarkdownTextToSelectedDraft()
    }

    private func syncCurrentMarkdownTextToSelectedDraft() {
        guard let selectedPostID else {
            return
        }

        draftContentByID[selectedPostID] = markdownText
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

private struct PendingImageImport: Identifiable {
    let id = UUID()
    let source: ImageImportSource
    let defaultName: String
    let insertionKind: ImageInsertionKind
}

private enum ImageInsertionKind {
    case image
    case figure

    var importTitle: String {
        switch self {
        case .image:
            "Import Image"
        case .figure:
            "Import Figure Image"
        }
    }
}

private enum ImageImportNaming {
    static func defaultName(forFileURL url: URL) -> String {
        sanitizedDisplayName(from: url.deletingPathExtension().lastPathComponent, fallback: "image")
    }

    static func defaultName(forImageData data: Data, fallbackDate: Date?) -> String {
        let metadata = imageMetadata(from: data)
        let descriptiveName = [metadata.title, metadata.description]
            .compactMap { nonEmptyString($0?.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .first

        if let descriptiveName {
            return sanitizedDisplayName(from: descriptiveName, fallback: datedFallbackName(from: fallbackDate))
        }

        return datedFallbackName(from: metadata.creationDate ?? fallbackDate)
    }

    private static func imageMetadata(from data: Data) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ImageMetadata(title: nil, description: nil, creationDate: nil)
        }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let title = stringValue(iptc?[kCGImagePropertyIPTCObjectName])
            ?? stringValue(tiff?[kCGImagePropertyTIFFImageDescription])
        let description = stringValue(iptc?[kCGImagePropertyIPTCCaptionAbstract])
        let creationDate = dateValue(exif?[kCGImagePropertyExifDateTimeOriginal])
            ?? dateValue(tiff?[kCGImagePropertyTIFFDateTime])

        return ImageMetadata(title: title, description: description, creationDate: creationDate)
    }

    private static func stringValue(_ value: Any?) -> String? {
        nonEmptyString((value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let value = stringValue(value) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }

    private static func datedFallbackName(from date: Date?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "photo-\(formatter.string(from: date ?? Date()))"
    }

    private static func sanitizedDisplayName(from value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let characters = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(characters)
            .split(whereSeparator: { $0 == "-" || $0 == " " || $0 == "\t" })
            .joined(separator: "-")
            .lowercased()

        return collapsed.isEmpty ? fallback : collapsed
    }
}

private struct ImageMetadata {
    let title: String?
    let description: String?
    let creationDate: Date?
}

private struct PendingSave {
    let itemID: String
    let item: HugoContentItem
    let contentToWrite: String
}

private struct InternalLinkRow: View {
    let item: HugoContentItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.section.localizedCaseInsensitiveCompare("posts") == .orderedSame ? "doc.text" : "doc.plaintext")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.sectionTitle)
                    Text(linkPath)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var linkPath: String {
        if let permalinkURL = URL(string: item.permalink), permalinkURL.scheme != nil {
            return permalinkURL.path.isEmpty ? "/" : permalinkURL.path
        }

        return item.permalink.isEmpty ? "/" : item.permalink
    }
}

private struct LayoutMetrics {
    let sidebarWidth: CGFloat
    let editorWidth: CGFloat
}

private struct DividerFeedback {
    let currentX: CGFloat?
    let minimumX: CGFloat
    let maximumX: CGFloat
}

private struct EditorDragStart {
    let sidebarWidth: CGFloat
    let editorWidth: CGFloat
}

private enum PaneDividerKind {
    case sidebar
    case editor
}

// NOTE: You will need to implement the WebView struct that wraps WKWebView for SwiftUI.
// See next steps for adding this.

#Preview {
    ContentView()
}
