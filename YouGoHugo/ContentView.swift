import SwiftUI
import AppKit
import TOMLKit

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
                .disabled(!siteIsOpen)
                
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
    }
    
    private func openSite() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    isLoading = true
                    errorMessage = nil
                }
                let configURL = url.appendingPathComponent("config.toml")
                DispatchQueue.global(qos: .userInitiated).async {
                    if FileManager.default.fileExists(atPath: configURL.path) {
                        do {
                            let content = try String(contentsOf: configURL, encoding: .utf8)
                            let decoder = TOMLDecoder()
                            let configResult = try decoder.decode(HugoConfig.self, from: content)
                            DispatchQueue.main.async {
                                config = configResult
                                configContent = content
                                siteURL = url
                                siteIsOpen = true
                                isLoading = false
                                errorMessage = nil
                            }
                        } catch {
                            DispatchQueue.main.async {
                                errorMessage = "Failed to load or parse config.toml: \(error.localizedDescription)"
                                isLoading = false
                                config = nil
                                configContent = nil
                                siteURL = nil
                                siteIsOpen = false
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            errorMessage = "No config.toml found in selected folder."
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
