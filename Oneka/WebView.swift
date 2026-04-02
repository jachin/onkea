import SwiftUI
import AppKit
import WebKit
import OSLog

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        if nsView.url != url {
            AppLogger.web.notice("Loading preview URL \(url.absoluteString, privacy: .public)")
            nsView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

extension WebView {
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            AppLogger.web.notice("Preview finished loading \(webView.url?.absoluteString ?? "<unknown>", privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            AppLogger.web.error("Preview navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            AppLogger.web.error("Preview provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            AppLogger.web.error("Web content process terminated for \(webView.url?.absoluteString ?? "<unknown>", privacy: .public)")
        }
    }
}
