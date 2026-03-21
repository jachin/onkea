import SwiftUI
import AppKit
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        if nsView.url != url {
            nsView.load(request)
        }
    }
}

