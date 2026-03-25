import SwiftUI
import AppKit
import Foundation
import OSLog

struct ContentView: View {
    @EnvironmentObject private var sidebarNavigation: SidebarNavigationModel

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
    @State private var contentErrorMessage: String? = nil
    @State private var hugoServerStatus = HugoServerStatus(phase: .stopped, message: "No server running", serverURL: nil)
    @State private var savedContentByID: [String: String] = [:]
    @State private var draftContentByID: [String: String] = [:]
    @State private var isSaving = false

    @State private var hugoStatus: HugoStatus = .checking

    private var filteredContentItems: [HugoContentItem] {
        switch sidebarNavigation.selectedTab {
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
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ContentSidebar(
                    isVisible: $showSidebar,
                    isSiteOpen: $siteIsOpen,
                    selectedPostID: $selectedPostID,
                    selectedTab: $sidebarNavigation.selectedTab,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    config: config,
                    contentItems: filteredContentItems,
                    contentErrorMessage: contentErrorMessage,
                    hasUnsavedChanges: hasUnsavedChanges(for:),
                    openSite: openSite,
                    createSite: { siteIsOpen = true /* TODO: implement creation */ }
                )
                if showSidebar {
                    Divider()
                }
                // Main 2-pane editor
                ZStack {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Markdown Editor")
                                    .font(.caption)
                                Spacer()
                            }
                            .padding(.top, 8)
                            MarkdownEditorView(text: $markdownText)
                                .padding([.leading, .trailing, .bottom], 8)
                        }
                        .frame(minWidth: 300, idealWidth: 400)
                        Divider()
                        VStack(alignment: .leading) {
                            Text("Preview")
                                .font(.caption)
                                .padding(.top, 8)
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
                            .padding([.leading, .trailing, .bottom], 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!siteIsOpen || hugoStatus != .compatible)

                    if !siteIsOpen {
                        Rectangle()
                            .fill(.thinMaterial)
                            .opacity(0.80)
                            .ignoresSafeArea()

                        if isLoading {
                            ProgressView("Loading site...")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        } else if let error = errorMessage {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.title3)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("Open or create a site to start editing")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Divider()
            serverStatusBar
        }
        .animation(.default, value: showSidebar)
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
        }
        .onDisappear {
            stopHugoServer(hugoServerProcess)
            hugoServerProcess = nil
            previewURL = nil
            hugoServerStatus = HugoServerStatus(phase: .stopped, message: "No server running", serverURL: nil)
        }
        .onChange(of: siteIsOpen) { _, newValue in
            sidebarNavigation.isSiteOpen = newValue
            if !newValue {
                sidebarNavigation.selectedTab = .posts
            }
        }
        .onChange(of: sidebarNavigation.selectedTab) { _, _ in
            syncSelectionWithVisibleTab()
        }
        .onChange(of: contentItems) { _, _ in
            syncSelectionWithVisibleTab()
        }
        .onChange(of: selectedPostID) { _, newValue in
            guard let newValue,
                  let siteURL,
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
                            contentItems = loadedContentItems
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
                            contentItems = []
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
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func updatePreviewURL(for item: HugoContentItem) {
        previewURL = previewURL(for: item, serverURL: hugoServerStatus.serverURL)
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

    private var canSaveSelectedPost: Bool {
        guard let selectedPostID, siteURL != nil else {
            return false
        }

        return hasUnsavedChanges(for: selectedPostID) && !isSaving
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

        let pendingSaves = itemIDs.compactMap { itemID -> PendingSave? in
            guard let item = contentItems.first(where: { $0.id == itemID }),
                  let draftContent = draftContentByID[itemID],
                  hasUnsavedChanges(for: itemID) else {
                return nil
            }

            return PendingSave(itemID: itemID, item: item, draftContent: draftContent)
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
                        try pendingSave.draftContent.write(to: fileURL, atomically: true, encoding: .utf8)
                    }
                }.value

                for pendingSave in pendingSaves {
                    AppLogger.content.notice("Saved content to \(pendingSave.item.path, privacy: .public)")
                }

                await MainActor.run {
                    for pendingSave in pendingSaves {
                        savedContentByID[pendingSave.itemID] = pendingSave.draftContent
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
    let draftContent: String
}

// NOTE: You will need to implement the WebView struct that wraps WKWebView for SwiftUI.
// See next steps for adding this.

#Preview {
    ContentView()
}
