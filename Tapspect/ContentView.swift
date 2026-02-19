import SwiftUI

private let brandBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
private let brandIndigo = Color(red: 0.388, green: 0.400, blue: 0.945)

// MARK: - Drawer Detent

enum DrawerDetent: CaseIterable {
    case mid, full

    /// Y-offset from the top of the screen to the top of the drawer.
    func offset(in screenHeight: CGFloat) -> CGFloat {
        switch self {
        case .mid:  return screenHeight * 0.55
        case .full: return screenHeight * 0.15
        }
    }
}

// MARK: - Scroll Offset Tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    @EnvironmentObject var screenshotService: ScreenshotService
    @AppStorage("webAppURL") private var webAppURL: String = ""
    @State private var urlInput: String = ""

    @StateObject private var webViewModel = WebViewModel()
    @State private var showDebugPanel = false
    @State private var selectedTab: DebugTab = .console
    @State private var fabPosition: CGPoint? = nil
    @State private var webViewReloadID: UUID = UUID()
    @State private var selectedScreenshot: ScreenshotEntry? = nil

    // Drawer state (Apple Maps-style)
    @State private var drawerOffset: CGFloat = 10000 // start off-screen; actual value set on appear
    @State private var drawerDetent: DrawerDetent = .mid
    @State private var drawerDragStartOffset: CGFloat? = nil
    @State private var contentAtTop: Bool = true

    // Console filters
    @State private var activeConsoleLevels: Set<ConsoleLog.LogLevel> = Set(ConsoleLog.LogLevel.allCases)

    // Network filters & detail
    @State private var networkFilterText: String = ""
    @State private var selectedNetworkRequest: NetworkRequest? = nil

    // Keychain-backed bindings for settings fields
    @State private var apiKeyInput: String = ""
    @State private var basicAuthUsernameInput: String = ""
    @State private var basicAuthPasswordInput: String = ""

    enum DebugTab: String, CaseIterable {
        case console = "Console"
        case network = "Network"
        case screenshots = "Screenshots"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .console: return "terminal"
            case .network: return "arrow.up.arrow.down"
            case .screenshots: return "camera"
            case .settings: return "gearshape"
            }
        }

        var isClearable: Bool {
            switch self {
            case .console, .network, .screenshots: return true
            case .settings: return false
            }
        }
    }

    var body: some View {
        GeometryReader { rootGeometry in
            let windowWidth = rootGeometry.size.width
            let windowHeight = rootGeometry.size.height + rootGeometry.safeAreaInsets.bottom

            ZStack {
                if webAppURL.isEmpty {
                    defineAppURLView
                } else if let loadError = webViewModel.loadError {
                    loadErrorView(error: loadError)
                } else {
                    WebView(viewModel: webViewModel, urlString: webAppURL)
                        .id("\(webAppURL)-\(webViewReloadID)")
                        .ignoresSafeArea(.container, edges: .bottom)
                }

                // Debug Panel (bottom sheet — Apple Maps-style)
                if showDebugPanel && !screenshotService.isCapturing {
                    let drawerHeight = max(windowHeight - drawerOffset, 0)
                    debugPanel(screenHeight: windowHeight)
                        .frame(height: drawerHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .onAppear {
                            // Animate in from below
                            drawerOffset = windowHeight
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                drawerOffset = drawerDetent.offset(in: windowHeight)
                            }
                        }
                        .ignoresSafeArea(.container, edges: .bottom)
                }

                // Floating Action Button (draggable) — hidden during screenshot capture
                if !screenshotService.isCapturing {
                    FloatingButton(
                        position: Binding(
                            get: { fabPosition ?? defaultFabPosition(width: windowWidth, height: windowHeight) },
                            set: { fabPosition = $0 }
                        ),
                        windowSize: CGSize(width: windowWidth, height: windowHeight),
                        isActive: showDebugPanel,
                        consoleCount: webViewModel.consoleLogs.count,
                        errorCount: webViewModel.errorCount
                    ) {
                        if showDebugPanel {
                            // Close
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                drawerOffset = windowHeight
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showDebugPanel = false
                                drawerDetent = .mid
                                contentAtTop = true
                            }
                        } else {
                            // Open
                            if webAppURL.isEmpty {
                                selectedTab = .settings
                            }
                            drawerDetent = .mid
                            contentAtTop = true
                            drawerOffset = windowHeight
                            showDebugPanel = true
                            // onAppear handles the animate-in
                        }
                    }
                    .accessibilityLabel(showDebugPanel ? "Close debug panel" : "Open debug panel")
                    .accessibilityHint(showDebugPanel ? "Closes the debugging drawer" : "Opens the debugging drawer")
                }

                // Toast overlay
                if let toast = screenshotService.toast {
                    ToastOverlay(message: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: screenshotService.toast)
                        .zIndex(100)
                        .accessibilityElement(children: .combine)
                }

                // Screenshot detail overlay
                if let entry = selectedScreenshot {
                    ScreenshotDetailOverlay(
                        entry: entry,
                        image: screenshotService.loadImage(for: entry),
                        onCopyURL: {
                            screenshotService.copyURL(entry)
                        },
                        onDismiss: {
                            withAnimation { selectedScreenshot = nil }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(99)
                }
            }
        }
        .onAppear {
            // Pre-fill URL input with current URL
            if urlInput.isEmpty && !webAppURL.isEmpty {
                urlInput = webAppURL
            }
            // Load Keychain values into local state
            apiKeyInput = screenshotService.apiKey
            basicAuthUsernameInput = screenshotService.basicAuthUsername
            basicAuthPasswordInput = screenshotService.basicAuthPassword
        }
        .preferredColorScheme(nil)
    }

    private func defaultFabPosition(width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: width - 50, y: height - 150)
    }

    // MARK: - Placeholder View (no URL configured)

    private var defineAppURLView: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "globe")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundColor(.gray.opacity(0.5))

                Text("No App URL Configured")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.gray)

                Button {
                    selectedTab = .settings
                    drawerDetent = .mid
                    contentAtTop = true
                    drawerOffset = 10000
                    showDebugPanel = true
                } label: {
                    Text("Define App URL")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(brandBlue)
                        .cornerRadius(12)
                }
                .accessibilityHint("Opens settings to configure the web app URL")
            }
        }
    }

    // MARK: - Load Error View

    private func loadErrorView(error: String) -> some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundColor(.red.opacity(0.6))

                Text("Failed to Load")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)

                Text(error)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    webViewModel.loadError = nil
                    webViewReloadID = UUID()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(brandBlue)
                    .cornerRadius(12)
                }
                .accessibilityLabel("Retry loading page")
            }
        }
    }

    // MARK: - Debug Panel

    private func debugPanel(screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            debugPanelHeader
            Divider().background(Color.gray.opacity(0.3))
            debugPanelContent
        }
        .background(
            // Embed the gesture coordinator inside the drawer's view tree
            // so it can find sibling UIScrollViews via the hosting view.
            DrawerGestureCoordinator(
                drawerAtFull: drawerDetent == .full,
                contentAtTop: contentAtTop,
                onDragChanged: { translation, _ in
                    handleDrawerDrag(translation: translation, screenHeight: screenHeight)
                },
                onDragEnded: { _, velocity in
                    handleDrawerDragEnd(velocity: velocity, screenHeight: screenHeight)
                }
            )
            .frame(width: 0, height: 0) // zero-size marker
        )
        .background(Color(white: 0.10).opacity(0.98))
        .clipShape(RoundedTopCorners(radius: 16))
    }

    private var debugPanelHeader: some View {
        VStack(spacing: 8) {
            // Visual drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .accessibilityLabel("Drag handle")
                .accessibilityHint("Drag to resize the debug panel")

            // Tab bar
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(DebugTab.allCases, id: \.self) { tab in
                            Button {
                                selectedTab = tab
                                contentAtTop = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 12))
                                    Text(tab.rawValue)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize()
                                    let count = badgeCountForTab(tab)
                                    if count > 0 {
                                        badgeView(count)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                            }
                            .foregroundColor(selectedTab == tab ? .white : .gray)
                            .accessibilityLabel("\(tab.rawValue) tab, \(badgeCountForTab(tab)) items")
                        }
                    }
                }

                // Action buttons
                HStack(spacing: 0) {
                    // Reload button
                    if !webAppURL.isEmpty {
                        Button {
                            webViewModel.loadError = nil
                            webViewReloadID = UUID()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .padding(8)
                        }
                        .accessibilityLabel("Reload web page")
                    }

                    // Copy all button (console & network only)
                    if selectedTab.isClearable {
                        Button {
                            copyTabContent()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .padding(8)
                        }
                        .accessibilityLabel("Copy all \(selectedTab.rawValue) content")
                    }

                    // Clear button (only for clearable tabs)
                    if selectedTab.isClearable {
                        Button {
                            if selectedTab == .console {
                                webViewModel.consoleLogs.removeAll()
                                webViewModel.errorCount = 0
                            } else if selectedTab == .network {
                                webViewModel.networkRequests.removeAll()
                            } else if selectedTab == .screenshots {
                                screenshotService.deleteAllScreenshots()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .padding(8)
                        }
                        .accessibilityLabel("Clear \(selectedTab.rawValue)")
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var debugPanelContent: some View {
        switch selectedTab {
        case .console:
            consoleView
        case .network:
            networkView
        case .screenshots:
            screenshotsView
        case .settings:
            settingsView
        }
    }

    private func badgeCountForTab(_ tab: DebugTab) -> Int {
        switch tab {
        case .console: return webViewModel.consoleLogs.count
        case .network: return webViewModel.networkRequests.count
        case .screenshots: return screenshotService.screenshots.count
        case .settings: return 0
        }
    }

    private func badgeView(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(8)
    }

    // MARK: - Settings View

    private var settingsView: some View {
        ScrollView {
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("settingsScroll")).minY
                    )
            }
            .frame(height: 0)

            VStack(alignment: .leading, spacing: 16) {
                // Section header
                Text("WEB APP URL")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding(.top, 12)

                // URL text field
                TextField("https://example.com", text: $urlInput)
                    .font(.system(size: 14, design: .monospaced))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(white: 0.14))
                    .cornerRadius(10)
                    .accessibilityLabel("Web app URL")

                // Current URL indicator
                if !webAppURL.isEmpty {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(webAppURL)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    .accessibilityLabel("Currently loaded URL: \(webAppURL)")
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        applyURL()
                    } label: {
                        Text("Load URL")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isValidURL(urlInput) ? brandBlue : Color.gray.opacity(0.3))
                            .cornerRadius(10)
                    }
                    .disabled(!isValidURL(urlInput))
                    .accessibilityHint("Loads the entered URL in the web view")

                    if !webAppURL.isEmpty {
                        Button {
                            urlInput = ""
                            webAppURL = ""
                            webViewModel.consoleLogs.removeAll()
                            webViewModel.errorCount = 0
                            webViewModel.networkRequests.removeAll()
                            webViewModel.loadError = nil
                        } label: {
                            Text("Clear")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(10)
                        }
                        .accessibilityLabel("Clear current URL")
                    }
                }
                Divider()
                    .background(Color.gray.opacity(0.3))
                    .padding(.vertical, 8)

                // Screenshot Upload section
                Text("SCREENSHOT UPLOAD")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)

                Toggle(isOn: $screenshotService.isEnabled) {
                    Text("Auto-upload screenshots")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                }
                .tint(brandBlue)

                if screenshotService.isEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upload Endpoint")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                        TextField("https://api.example.com/upload", text: $screenshotService.uploadURL)
                            .font(.system(size: 14, design: .monospaced))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(white: 0.14))
                            .cornerRadius(10)
                            .accessibilityLabel("Upload endpoint URL")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Form Field Name")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                        TextField("file", text: $screenshotService.fieldName)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(white: 0.14))
                            .cornerRadius(10)
                            .accessibilityLabel("Multipart form field name")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Basic Auth Username")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                        TextField("username", text: $basicAuthUsernameInput)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(white: 0.14))
                            .cornerRadius(10)
                            .accessibilityLabel("Basic auth username")
                            .onChange(of: basicAuthUsernameInput) { _, newValue in
                                screenshotService.basicAuthUsername = newValue
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Basic Auth Password")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                        SecureField("password", text: $basicAuthPasswordInput)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(white: 0.14))
                            .cornerRadius(10)
                            .accessibilityLabel("Basic auth password")
                            .onChange(of: basicAuthPasswordInput) { _, newValue in
                                screenshotService.basicAuthPassword = newValue
                            }
                        Text("Leave empty if not using basic auth")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.6))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key Header")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                        TextField("Authorization", text: $screenshotService.apiKeyHeader)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(white: 0.14))
                            .cornerRadius(10)
                            .accessibilityLabel("API key header name")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key Value")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                        SecureField("Bearer token or API key", text: $apiKeyInput)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(white: 0.14))
                            .cornerRadius(10)
                            .accessibilityLabel("API key value")
                            .onChange(of: apiKeyInput) { _, newValue in
                                screenshotService.apiKey = newValue
                            }
                        Text("Ignored when basic auth is set")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.6))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Response URL Key Path")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                        TextField("url", text: $screenshotService.responseURLKeyPath)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(white: 0.14))
                            .cornerRadius(10)
                            .accessibilityLabel("Response URL key path")
                        Text("Dot-separated path in JSON response (e.g. data.url)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .coordinateSpace(name: "settingsScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            if selectedTab == .settings { contentAtTop = offset >= 0 }
        }
        .scrollDisabled(drawerDetent != .full)
        .accessibilityIdentifier(DrawerPanController.verticalScrollTag)
    }

    private func applyURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidURL(trimmed) else { return }
        webAppURL = trimmed
        webViewModel.consoleLogs.removeAll()
        webViewModel.errorCount = 0
        webViewModel.networkRequests.removeAll()
        webViewModel.loadError = nil
    }

    private func isValidURL(_ string: String) -> Bool {
        isValidWebURL(string)
    }

    // MARK: - Drawer Gesture Handling

    private func handleDrawerDrag(translation: CGFloat, screenHeight: CGFloat) {
        if drawerDragStartOffset == nil {
            drawerDragStartOffset = drawerOffset
        }
        let start = drawerDragStartOffset!
        let newOffset = start + translation

        // Clamp: don't go above full, allow overscroll below for close
        let fullOffset = DrawerDetent.full.offset(in: screenHeight)
        let maxOffset = screenHeight + 50
        drawerOffset = min(max(newOffset, fullOffset - 20), maxOffset)
    }

    private func handleDrawerDragEnd(velocity: CGFloat, screenHeight: CGFloat) {
        drawerDragStartOffset = nil

        let midOffset = DrawerDetent.mid.offset(in: screenHeight)
        let fullOffset = DrawerDetent.full.offset(in: screenHeight)
        let midpoint = (midOffset + fullOffset) / 2

        // Close: fast downward swipe, or dragged below mid position
        if velocity > 600 || drawerOffset > midOffset + 40 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                drawerOffset = screenHeight
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showDebugPanel = false
                drawerDetent = .mid
                contentAtTop = true
            }
            return
        }

        // Snap to full or mid based on position and velocity
        let targetDetent: DrawerDetent
        if velocity < -400 {
            targetDetent = .full
        } else if velocity > 200 {
            targetDetent = .mid
        } else {
            targetDetent = drawerOffset < midpoint ? .full : .mid
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            drawerDetent = targetDetent
            drawerOffset = targetDetent.offset(in: screenHeight)
        }
    }

    /// Copy all content from the current tab to the system clipboard.
    private func copyTabContent() {
        let text: String
        switch selectedTab {
        case .console:
            text = webViewModel.consoleLogs.map { log in
                "[\(log.level.rawValue.uppercased())] \(log.timestamp) \(log.message)"
            }.joined(separator: "\n")
        case .network:
            text = webViewModel.networkRequests.map { req in
                let status = req.statusCode.map { "\($0)" } ?? "---"
                let duration = req.duration.map { String(format: "%.0fms", $0 * 1000) } ?? "---"
                return "\(req.method) \(status) \(duration) \(req.url) [\(req.timestamp)]"
            }.joined(separator: "\n")
        case .screenshots:
            text = screenshotService.screenshots.map { entry in
                "\(entry.formattedTimestamp) \(entry.publicURL)"
            }.joined(separator: "\n")
        case .settings:
            return
        }
        UIPasteboard.general.string = text
    }

    // MARK: - Console View

    private var filteredConsoleLogs: [ConsoleLog] {
        webViewModel.consoleLogs.filter { activeConsoleLevels.contains($0.level) }
    }

    private var consoleView: some View {
        VStack(spacing: 0) {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ConsoleLog.LogLevel.allCases, id: \.self) { level in
                        let isActive = activeConsoleLevels.contains(level)
                        Button {
                            if isActive {
                                activeConsoleLevels.remove(level)
                            } else {
                                activeConsoleLevels.insert(level)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(level.color)
                                    .frame(width: 6, height: 6)
                                Text(level.rawValue.capitalized)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(isActive ? level.color.opacity(0.15) : Color(white: 0.14))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isActive ? level.color.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }
                        .foregroundColor(isActive ? .white : .gray)
                        .accessibilityLabel("\(level.rawValue.capitalized) filter, \(isActive ? "active" : "inactive")")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider().background(Color.gray.opacity(0.2))

            // Log list
            ScrollViewReader { proxy in
                ScrollView {
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("consoleScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredConsoleLogs) { log in
                            consoleLogRow(log)
                                .id(log.id)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, 16)
                }
                .coordinateSpace(name: "consoleScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { offset in
                    if selectedTab == .console { contentAtTop = offset >= 0 }
                }
                .scrollDisabled(drawerDetent != .full)
                .accessibilityIdentifier(DrawerPanController.verticalScrollTag)
                .onChange(of: webViewModel.consoleLogs.count) { _, _ in
                    if let last = filteredConsoleLogs.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func consoleLogRow(_ log: ConsoleLog) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(log.level.color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(log.level.textColor)
                    .textSelection(.enabled)

                Text(log.timestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.6))
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(log.level == .error ? Color.red.opacity(0.08) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(log.level.rawValue) log: \(log.message)")
    }

    // MARK: - Network View

    private var filteredNetworkRequests: [NetworkRequest] {
        if networkFilterText.isEmpty {
            return webViewModel.networkRequests
        }
        let filter = networkFilterText.lowercased()
        return webViewModel.networkRequests.filter {
            $0.url.lowercased().contains(filter) ||
            $0.method.lowercased().contains(filter) ||
            ($0.statusCode.map { String($0).contains(filter) } ?? false)
        }
    }

    private var networkView: some View {
        ZStack {
            VStack(spacing: 0) {
                // Filter input
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    TextField("Filter requests…", text: $networkFilterText)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Filter network requests")
                    if !networkFilterText.isEmpty {
                        Button {
                            networkFilterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .accessibilityLabel("Clear filter")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.14))

                Divider().background(Color.gray.opacity(0.2))

                // Request list
                ScrollView {
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("networkScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredNetworkRequests) { request in
                            Button {
                                selectedNetworkRequest = request
                            } label: {
                                networkRow(request)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, 16)
                }
                .coordinateSpace(name: "networkScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { offset in
                    if selectedTab == .network { contentAtTop = offset >= 0 }
                }
                .scrollDisabled(drawerDetent != .full)
                .accessibilityIdentifier(DrawerPanController.verticalScrollTag)
            }

            // Detail overlay
            if let request = selectedNetworkRequest {
                NetworkRequestDetailView(request: request) {
                    selectedNetworkRequest = nil
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedNetworkRequest?.id)
    }

    // MARK: - Screenshots View

    private var screenshotsView: some View {
        Group {
            if screenshotService.screenshots.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "camera.badge.clock")
                        .font(.system(size: 32, weight: .thin))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No screenshots yet")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))
                    Text("Take a screenshot to get started")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.4))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("screenshotsScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    LazyVStack(spacing: 0) {
                        ForEach(screenshotService.screenshots) { entry in
                            Button {
                                withAnimation { selectedScreenshot = entry }
                            } label: {
                                screenshotRow(entry)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .contextMenu {
                                Button {
                                    screenshotService.copyURL(entry)
                                } label: {
                                    Label("Copy URL", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    screenshotService.deleteScreenshot(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            Divider()
                                .background(Color.gray.opacity(0.2))
                                .padding(.leading, 12)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, 16)
                }
                .coordinateSpace(name: "screenshotsScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { offset in
                    if selectedTab == .screenshots { contentAtTop = offset >= 0 }
                }
                .scrollDisabled(drawerDetent != .full)
                .accessibilityIdentifier(DrawerPanController.verticalScrollTag)
            }
        }
    }

    private func screenshotRow(_ entry: ScreenshotEntry) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let image = screenshotService.loadImage(for: entry) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.14))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundColor(.gray.opacity(0.5))
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.publicURL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)

                Text(entry.formattedTimestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.4))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Screenshot at \(entry.formattedTimestamp)")
    }

    private func networkRow(_ request: NetworkRequest) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(request.method)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(request.methodColor)
                        .cornerRadius(4)

                    if let status = request.statusCode {
                        Text("\(status)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(status < 400 ? .green : .red)
                    }

                    if let duration = request.duration {
                        Text(String(format: "%.0fms", duration * 1000))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Text(request.timestamp)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))
                }

                Text(request.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.gray.opacity(0.4))
                .padding(.leading, 6)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            request.statusCode.map { $0 >= 400 } == true
                ? Color.red.opacity(0.08)
                : Color.clear
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(request.method) \(request.statusCode.map { "\($0)" } ?? "pending") \(request.url)")
    }
}

// MARK: - Network Request Detail View

struct NetworkRequestDetailView: View {
    let request: NetworkRequest
    let onDismiss: () -> Void

    enum DetailTab: String, CaseIterable {
        case request = "Request"
        case response = "Response"
    }

    @State private var selectedTab: DetailTab = .request

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(brandBlue)
                }
                .accessibilityLabel("Back to network list")

                Spacer()

                Text(request.method)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(request.methodColor)
                    .cornerRadius(4)

                if let status = request.statusCode {
                    Text("\(status)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(status < 400 ? .green : .red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // URL
            Text(request.url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // Tab switcher
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(selectedTab == tab ? .white : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
                    }
                    .accessibilityLabel("\(tab.rawValue) tab")
                }
            }
            .background(Color(white: 0.08))

            Divider().background(Color.gray.opacity(0.2))

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .request:
                        requestDetailContent
                    case .response:
                        responseDetailContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .background(Color(white: 0.10).opacity(0.98))
    }

    // MARK: - Request Tab Content

    private var requestDetailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Request info
            detailSection("GENERAL") {
                detailRow("Method", request.method)
                detailRow("URL", request.url)
                if let status = request.statusCode {
                    detailRow("Status", "\(status)")
                }
                if let duration = request.duration {
                    detailRow("Duration", String(format: "%.0fms", duration * 1000))
                }
                detailRow("Timestamp", request.timestamp)
            }

            // Request headers
            if let headers = request.requestHeaders, !headers.isEmpty {
                detailSection("REQUEST HEADERS") {
                    ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        detailRow(key, value)
                    }
                }
            }

            // Request body
            if let body = request.requestBody, !body.isEmpty {
                detailSection("REQUEST BODY") {
                    formattedBodyView(body, contentType: nil)
                }
            }

            if request.requestHeaders == nil && request.requestBody == nil {
                Text("No request data captured")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            }
        }
    }

    // MARK: - Response Tab Content

    private var responseDetailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Response headers
            if let headers = request.responseHeaders, !headers.isEmpty {
                detailSection("RESPONSE HEADERS") {
                    ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        detailRow(key, value)
                    }
                }
            }

            // Response body
            if let body = request.responseBody, !body.isEmpty {
                detailSection("RESPONSE BODY") {
                    formattedBodyView(body, contentType: request.responseContentType)
                }
            }

            if (request.responseHeaders == nil || request.responseHeaders?.isEmpty == true) &&
               (request.responseBody == nil || request.responseBody?.isEmpty == true) {
                Text("No response data captured")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            }
        }
    }

    // MARK: - Helpers

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.gray)
                .padding(.bottom, 2)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .cornerRadius(8)
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(brandBlue.opacity(0.8))
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func formattedBodyView(_ body: String, contentType: String?) -> some View {
        let ct = (contentType ?? "").lowercased()
        if ct.contains("image") {
            // Show image info — we have a URL reference but not raw data
            Text("[Image: \(ct)]")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)
                .italic()
        } else if ct.contains("json") || body.trimmingCharacters(in: .whitespaces).hasPrefix("{") || body.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            // Try to pretty-print JSON
            let pretty = prettyFormatJSON(body)
            Text(pretty)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .textSelection(.enabled)
        } else {
            Text(body)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Floating Button

struct FloatingButton: View {
    @Binding var position: CGPoint
    let windowSize: CGSize
    let isActive: Bool
    let consoleCount: Int
    let errorCount: Int
    let action: () -> Void

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Glass button visual — hit testing disabled so gestures aren't swallowed
            GlassEffectContainer {
                ZStack {
                    // Error badge
                    if errorCount > 0 && !isActive {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Text("\(errorCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 18, y: -18)
                            .zIndex(1)
                    }

                    Image(systemName: isActive ? "xmark" : "ladybug")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isActive ? .black : brandBlue)
                        .frame(width: 52, height: 52)
                        .glassEffect(
                            isActive
                                ? .regular.tint(brandBlue)
                                : .regular,
                            in: .circle
                        )
                }
            }
            .allowsHitTesting(false)

            // Transparent touch target — above the glass layer, catches all touches
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .position(
            x: position.x + dragOffset.width,
            y: position.y + dragOffset.height
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let distance = sqrt(
                        value.translation.width * value.translation.width +
                        value.translation.height * value.translation.height
                    )

                    if distance < 10 {
                        // Tap — no meaningful drag
                        dragOffset = .zero
                        action()
                    } else {
                        // Drag — snap to edge
                        position.x += value.translation.width
                        position.y += value.translation.height
                        dragOffset = .zero

                        withAnimation(.spring(response: 0.3)) {
                            if position.x < windowSize.width / 2 {
                                position.x = 40
                            } else {
                                position.x = windowSize.width - 40
                            }
                            position.y = min(max(position.y, 60), windowSize.height - 60)
                        }
                    }
                }
        )
    }
}

// MARK: - Toast Overlay

struct ToastOverlay: View {
    let message: ToastMessage

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: message.style == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(message.style == .success ? .green : .red)

                Text(message.message)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12).opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 24)
            .padding(.top, 60)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.style == .success ? "Success: \(message.message)" : "Error: \(message.message)")
    }
}

// MARK: - Screenshot Detail Overlay

struct ScreenshotDetailOverlay: View {
    let entry: ScreenshotEntry
    let image: UIImage?
    let onCopyURL: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 16) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                    }
                    .accessibilityLabel("Close screenshot detail")
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                // Screenshot image
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .accessibilityLabel("Screenshot image")
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.14))
                        .aspectRatio(9/16, contentMode: .fit)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.system(size: 32))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("Image not available")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                        )
                        .padding(.horizontal, 20)
                }

                // URL + timestamp
                VStack(spacing: 8) {
                    Button(action: onCopyURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                            Text(entry.publicURL)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(2)
                        }
                        .foregroundColor(brandBlue)
                    }
                    .accessibilityLabel("Copy URL: \(entry.publicURL)")

                    Text(entry.formattedTimestamp)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
    }
}

// MARK: - Rounded Top Corners

struct RoundedTopCorners: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
