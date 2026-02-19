import SwiftUI
import WebKit

// MARK: - Data Models

struct ConsoleLog: Identifiable {
    let id = UUID()
    let level: LogLevel
    let message: String
    let timestamp: String

    enum LogLevel: String, CaseIterable {
        case log, info, warn, error, debug

        var color: Color {
            switch self {
            case .log:   return .white.opacity(0.5)
            case .info:  return .blue
            case .warn:  return .yellow
            case .error: return .red
            case .debug: return .purple
            }
        }

        var textColor: Color {
            switch self {
            case .error: return Color(red: 1, green: 0.5, blue: 0.5)
            case .warn:  return Color(red: 1, green: 0.9, blue: 0.5)
            default:     return .white.opacity(0.85)
            }
        }
    }
}

struct NetworkRequest: Identifiable {
    let id = UUID()
    let method: String
    let url: String
    let statusCode: Int?
    let duration: Double? // seconds
    let timestamp: String
    let requestHeaders: [String: String]?
    let requestBody: String?
    let responseHeaders: [String: String]?
    let responseBody: String?
    let responseContentType: String?

    var methodColor: Color {
        switch method.uppercased() {
        case "GET":    return .green
        case "POST":   return .blue
        case "PUT":    return .yellow
        case "DELETE": return .red
        case "PATCH":  return .purple
        default:       return .gray
        }
    }
}

// MARK: - ViewModel

class WebViewModel: ObservableObject {
    @Published var consoleLogs: [ConsoleLog] = []
    @Published var networkRequests: [NetworkRequest] = []
    @Published var errorCount: Int = 0
    @Published var loadError: String? = nil

    static let maxLogEntries = 5000
    static let maxNetworkEntries = 2000

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    func addConsoleLog(level: String, message: String) {
        let log = ConsoleLog(
            level: ConsoleLog.LogLevel(rawValue: level) ?? .log,
            message: message,
            timestamp: dateFormatter.string(from: Date())
        )
        DispatchQueue.main.async {
            if self.consoleLogs.count >= Self.maxLogEntries {
                self.consoleLogs.removeFirst(self.consoleLogs.count - Self.maxLogEntries + 1)
            }
            self.consoleLogs.append(log)
            if log.level == .error {
                self.errorCount += 1
            }
        }
    }

    func addNetworkRequest(method: String, url: String, status: Int?, duration: Double?,
                            requestHeaders: [String: String]? = nil, requestBody: String? = nil,
                            responseHeaders: [String: String]? = nil, responseBody: String? = nil,
                            responseContentType: String? = nil) {
        let request = NetworkRequest(
            method: method,
            url: url,
            statusCode: status,
            duration: duration,
            timestamp: dateFormatter.string(from: Date()),
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            responseContentType: responseContentType
        )
        DispatchQueue.main.async {
            if self.networkRequests.count >= Self.maxNetworkEntries {
                self.networkRequests.removeFirst(self.networkRequests.count - Self.maxNetworkEntries + 1)
            }
            self.networkRequests.append(request)
        }
    }
}

// MARK: - WebView

struct WebView: UIViewRepresentable {
    @ObservedObject var viewModel: WebViewModel
    let urlString: String

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Inject JavaScript to intercept console and network
        let script = WKUserScript(
            source: Self.injectedJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(script)

        // Register message handlers
        config.userContentController.add(context.coordinator, name: "consoleLog")
        config.userContentController.add(context.coordinator, name: "networkLog")

        // Allow inline media playback
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.overrideUserInterfaceStyle = .unspecified

        // Store reference for cleanup
        context.coordinator.webView = webView

        // Load the URL
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "consoleLog")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "networkLog")
        coordinator.webView = nil
    }

    // MARK: - Injected JavaScript

    static let injectedJavaScript = """
    (function() {
        // ── Console Interception ──────────────────────────────────
        const originalConsole = {
            log: console.log,
            info: console.info,
            warn: console.warn,
            error: console.error,
            debug: console.debug
        };

        function stringify(args) {
            return Array.from(args).map(arg => {
                if (arg === null) return 'null';
                if (arg === undefined) return 'undefined';
                if (typeof arg === 'object') {
                    try { return JSON.stringify(arg, null, 2); }
                    catch(e) { return String(arg); }
                }
                return String(arg);
            }).join(' ');
        }

        ['log', 'info', 'warn', 'error', 'debug'].forEach(level => {
            console[level] = function() {
                originalConsole[level].apply(console, arguments);
                try {
                    window.webkit.messageHandlers.consoleLog.postMessage({
                        level: level,
                        message: stringify(arguments)
                    });
                } catch(e) {}
            };
        });

        // Capture uncaught errors
        window.addEventListener('error', function(e) {
            window.webkit.messageHandlers.consoleLog.postMessage({
                level: 'error',
                message: e.message + ' at ' + e.filename + ':' + e.lineno + ':' + e.colno
            });
        });

        // Capture unhandled promise rejections
        window.addEventListener('unhandledrejection', function(e) {
            window.webkit.messageHandlers.consoleLog.postMessage({
                level: 'error',
                message: 'Unhandled Promise Rejection: ' + (e.reason?.message || e.reason || 'unknown')
            });
        });

        // ── Helpers ────────────────────────────────────────────────
        function headersToObj(headers) {
            var obj = {};
            if (headers && typeof headers.forEach === 'function') {
                headers.forEach(function(v, k) { obj[k] = v; });
            } else if (headers && typeof headers === 'object') {
                Object.keys(headers).forEach(function(k) { obj[k] = headers[k]; });
            }
            return obj;
        }

        function truncate(str, max) {
            if (!str) return str;
            return str.length > max ? str.substring(0, max) + '… (truncated)' : str;
        }

        // ── Network Interception (fetch) ──────────────────────────
        const originalFetch = window.fetch;
        window.fetch = function() {
            const startTime = performance.now();
            const input = arguments[0];
            const init = arguments[1] || {};
            const url = input instanceof Request ? input.url : String(input);
            const method = (init.method || (input instanceof Request ? input.method : 'GET')).toUpperCase();

            var reqHeaders = {};
            if (init.headers) {
                if (init.headers instanceof Headers) {
                    reqHeaders = headersToObj(init.headers);
                } else {
                    reqHeaders = Object.assign({}, init.headers);
                }
            } else if (input instanceof Request) {
                reqHeaders = headersToObj(input.headers);
            }

            var reqBody = null;
            if (init.body) {
                if (typeof init.body === 'string') reqBody = truncate(init.body, 32000);
                else { try { reqBody = truncate(JSON.stringify(init.body), 32000); } catch(e) { reqBody = '[binary]'; } }
            }

            return originalFetch.apply(this, arguments).then(function(response) {
                const duration = (performance.now() - startTime) / 1000;
                var resHeaders = headersToObj(response.headers);
                var contentType = response.headers.get('content-type') || '';

                var cloned = response.clone();
                cloned.text().then(function(bodyText) {
                    try {
                        window.webkit.messageHandlers.networkLog.postMessage({
                            method: method, url: url, status: response.status, duration: duration,
                            requestHeaders: reqHeaders, requestBody: reqBody,
                            responseHeaders: resHeaders, responseBody: truncate(bodyText, 64000),
                            responseContentType: contentType
                        });
                    } catch(e) {}
                }).catch(function() {
                    try {
                        window.webkit.messageHandlers.networkLog.postMessage({
                            method: method, url: url, status: response.status, duration: duration,
                            requestHeaders: reqHeaders, requestBody: reqBody,
                            responseHeaders: resHeaders, responseBody: null,
                            responseContentType: contentType
                        });
                    } catch(e) {}
                });
                return response;
            }).catch(function(error) {
                const duration = (performance.now() - startTime) / 1000;
                try {
                    window.webkit.messageHandlers.networkLog.postMessage({
                        method: method, url: url, status: 0, duration: duration,
                        requestHeaders: reqHeaders, requestBody: reqBody,
                        responseHeaders: null, responseBody: null, responseContentType: null
                    });
                } catch(e) {}
                throw error;
            });
        };

        // ── Network Interception (XMLHttpRequest) ─────────────────
        const OriginalXHR = XMLHttpRequest;
        const originalOpen = OriginalXHR.prototype.open;
        const originalSend = OriginalXHR.prototype.send;
        const originalSetHeader = OriginalXHR.prototype.setRequestHeader;

        OriginalXHR.prototype.open = function(method, url) {
            this._debugMethod = method.toUpperCase();
            this._debugURL = url;
            this._debugReqHeaders = {};
            return originalOpen.apply(this, arguments);
        };

        OriginalXHR.prototype.setRequestHeader = function(name, value) {
            if (this._debugReqHeaders) this._debugReqHeaders[name] = value;
            return originalSetHeader.apply(this, arguments);
        };

        OriginalXHR.prototype.send = function(body) {
            const startTime = performance.now();
            const xhr = this;
            var reqBody = null;
            if (body) {
                if (typeof body === 'string') reqBody = truncate(body, 32000);
                else { try { reqBody = truncate(JSON.stringify(body), 32000); } catch(e) { reqBody = '[binary]'; } }
            }

            this.addEventListener('loadend', function() {
                const duration = (performance.now() - startTime) / 1000;
                var resHeaders = {};
                try {
                    var raw = xhr.getAllResponseHeaders() || '';
                    raw.trim().split('\\r\\n').forEach(function(line) {
                        var parts = line.split(': ');
                        if (parts.length >= 2) resHeaders[parts[0]] = parts.slice(1).join(': ');
                    });
                } catch(e) {}
                var contentType = xhr.getResponseHeader('content-type') || '';
                try {
                    window.webkit.messageHandlers.networkLog.postMessage({
                        method: xhr._debugMethod || 'GET',
                        url: xhr._debugURL || '',
                        status: xhr.status,
                        duration: duration,
                        requestHeaders: xhr._debugReqHeaders || {},
                        requestBody: reqBody,
                        responseHeaders: resHeaders,
                        responseBody: truncate(xhr.responseText, 64000),
                        responseContentType: contentType
                    });
                } catch(e) {}
            });

            return originalSend.apply(this, arguments);
        };
    })();
    """

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let viewModel: WebViewModel
        weak var webView: WKWebView?

        init(viewModel: WebViewModel) {
            self.viewModel = viewModel
        }

        // Handle messages from JavaScript
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else { return }

            switch message.name {
            case "consoleLog":
                let level = body["level"] as? String ?? "log"
                let msg = body["message"] as? String ?? ""
                viewModel.addConsoleLog(level: level, message: msg)

            case "networkLog":
                let method = body["method"] as? String ?? "GET"
                let url = body["url"] as? String ?? ""
                let status = body["status"] as? Int
                let duration = body["duration"] as? Double
                let reqHeaders = body["requestHeaders"] as? [String: String]
                let reqBody = body["requestBody"] as? String
                let resHeaders = body["responseHeaders"] as? [String: String]
                let resBody = body["responseBody"] as? String
                let resContentType = body["responseContentType"] as? String
                viewModel.addNetworkRequest(
                    method: method, url: url, status: status, duration: duration,
                    requestHeaders: reqHeaders, requestBody: reqBody,
                    responseHeaders: resHeaders, responseBody: resBody,
                    responseContentType: resContentType
                )

            default:
                break
            }
        }

        // Track navigation as network requests
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.loadError = nil
            }
            if let url = webView.url?.absoluteString {
                viewModel.addConsoleLog(level: "info", message: "⇢ Navigating to: \(url)")
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url?.absoluteString {
                viewModel.addConsoleLog(level: "info", message: "✓ Loaded: \(url)")
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            // Ignore cancellation errors (e.g. user navigated away)
            guard nsError.code != NSURLErrorCancelled else { return }
            viewModel.addConsoleLog(level: "error", message: "✗ Navigation failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.viewModel.loadError = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            viewModel.addConsoleLog(level: "error", message: "✗ Failed to load: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.viewModel.loadError = error.localizedDescription
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""

            // Allow http and https normally
            if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "blob" || scheme == "data" {
                decisionHandler(.allow)
                return
            }

            // For other schemes (tel:, mailto:, itms-apps:, etc.), open externally
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
