import SwiftUI
import AppKit
import Foundation
import OSLog

struct ContentView: View {
    @State private var showSidebar = true
    @State private var selectedPost: String? = nil
    @State private var markdownText: String = ""
    @State private var siteIsOpen = false

    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var configContent: String? = nil
    @State private var siteURL: URL? = nil
    @State private var config: HugoConfig? = nil

    @State private var hugoStatus: HugoStatus = .checking

    // Mock post titles; replace with your actual posts later.
    let postTitles = [
        "Welcome to Hugo",
        "Getting Started Guide",
        "Markdown Syntax Tips",
        "Deploying Your Site"
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Posts")
                            .font(.headline)
                        Spacer()
                        Button(action: { showSidebar = false }) {
                            Image(systemName: "sidebar.left")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    if !siteIsOpen {
                        VStack(spacing: 16) {
                            Text("No site open")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Open Site") { openSite() }
                            Button("Create New Site") { siteIsOpen = true /* TODO: implement creation */ }
                            if isLoading {
                                ProgressView("Loading site...")
                                    .padding(.top)
                            }
                            if let error = errorMessage {
                                Text(error)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            if let siteTitle = config?.title {
                                Text(siteTitle)
                                    .font(.title3)
                                    .bold()
                                    .padding(.horizontal)
                            }
                            List(selection: $selectedPost) {
                                ForEach(postTitles, id: \.self) { title in
                                    Text(title)
                                        .tag(title as String?)
                                }
                            }
                            .listStyle(.inset)
                        }
                    }
                }
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
                .transition(.move(edge: .leading))
            } else {
                VStack {
                    Button(action: { showSidebar = true }) {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(width: 20)
            }
            Divider()
            // Main 2-pane editor
            ZStack {
                HStack(spacing: 0) {
                    VStack(alignment: .leading) {
                        Text("Markdown Editor")
                            .font(.caption)
                            .padding(.top, 8)
                        TextEditor(text: $markdownText)
                            .font(.system(.body, design: .monospaced))
                            .padding([.leading, .trailing, .bottom], 8)
                    }
                    .frame(minWidth: 300, idealWidth: 400)
                    Divider()
                    VStack(alignment: .leading) {
                        Text("Preview")
                            .font(.caption)
                            .padding(.top, 8)
                        WebView(url: URL(string: "http://localhost:1313")!)
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
        .animation(.default, value: showSidebar)
        .onChange(of: selectedPost) { _, newValue in
            if let title = newValue {
                markdownText = "# \(title)\n\nThis is a mock post. Replace with real post content."
            }
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
                        DispatchQueue.main.async {
                            config = configResult
                            configContent = nil
                            siteURL = url
                            siteIsOpen = true
                            isLoading = false
                            errorMessage = nil
                        }
                    } catch {
                        AppLogger.app.error("Failed to load Hugo config for site at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        DispatchQueue.main.async {
                            errorMessage = "Failed to load Hugo config: \(error.localizedDescription)"
                            isLoading = false
                            config = nil
                            configContent = nil
                            siteURL = nil
                            siteIsOpen = false
                        }
                    }
                }
            }
        }
    }
}

// NOTE: You will need to implement the WebView struct that wraps WKWebView for SwiftUI.
// See next steps for adding this.

#Preview {
    ContentView()
}
