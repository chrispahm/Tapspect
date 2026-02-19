import SwiftUI

// MARK: - Toast Model

enum ToastStyle {
    case success
    case error
}

struct ToastMessage: Equatable {
    let id = UUID()
    let message: String
    let style: ToastStyle

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Screenshot Entry Model

struct ScreenshotEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let publicURL: String
    let localImageFilename: String // filename only, resolved against Documents dir

    private static let sharedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var formattedTimestamp: String {
        Self.sharedFormatter.string(from: timestamp)
    }
}

// MARK: - Screenshot Service

class ScreenshotService: ObservableObject {
    @Published var toast: ToastMessage? = nil
    @Published var screenshots: [ScreenshotEntry] = []
    @Published var isCapturing: Bool = false

    @AppStorage("screenshotUploadEnabled") var isEnabled: Bool = false
    @AppStorage("screenshotUploadURL") var uploadURL: String = ""
    @AppStorage("screenshotUploadFieldName") var fieldName: String = "file"
    @AppStorage("screenshotUploadAPIKeyHeader") var apiKeyHeader: String = "Authorization"
    @AppStorage("screenshotResponseURLKeyPath") var responseURLKeyPath: String = "url"

    // Keychain-backed credential properties
    var apiKey: String {
        get { KeychainService.load(key: "screenshotUploadAPIKey") }
        set { KeychainService.save(key: "screenshotUploadAPIKey", value: newValue); objectWillChange.send() }
    }

    var basicAuthUsername: String {
        get { KeychainService.load(key: "screenshotBasicAuthUsername") }
        set { KeychainService.save(key: "screenshotBasicAuthUsername", value: newValue); objectWillChange.send() }
    }

    var basicAuthPassword: String {
        get { KeychainService.load(key: "screenshotBasicAuthPassword") }
        set { KeychainService.save(key: "screenshotBasicAuthPassword", value: newValue); objectWillChange.send() }
    }

    static let maxScreenshots = 200

    private var notificationObserver: Any?

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var screenshotsDirectory: URL {
        documentsDirectory.appendingPathComponent("screenshots", isDirectory: true)
    }

    private var historyFileURL: URL {
        documentsDirectory.appendingPathComponent("screenshots.json")
    }

    init() {
        ensureScreenshotsDirectory()
        loadHistory()
        migrateFromUserDefaults()
        startObserving()
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Migration from UserDefaults to Keychain

    private func migrateFromUserDefaults() {
        let defaults = UserDefaults.standard
        let keysToMigrate = [
            ("screenshotUploadAPIKey", "screenshotUploadAPIKey"),
            ("screenshotBasicAuthUsername", "screenshotBasicAuthUsername"),
            ("screenshotBasicAuthPassword", "screenshotBasicAuthPassword"),
        ]
        for (defaultsKey, keychainKey) in keysToMigrate {
            if let value = defaults.string(forKey: defaultsKey), !value.isEmpty {
                KeychainService.save(key: keychainKey, value: value)
                defaults.removeObject(forKey: defaultsKey)
            }
        }
    }

    // MARK: - Observation

    private func startObserving() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenshot()
        }
    }

    // MARK: - Screenshot Handling

    private func handleScreenshot() {
        guard isEnabled else { return }
        guard !uploadURL.isEmpty, URL(string: uploadURL) != nil else {
            showToast("Screenshot upload URL not configured", style: .error)
            return
        }

        // Hide FAB and other overlays, then capture after a brief layout pass
        isCapturing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            self.performCapture()
        }
    }

    private func performCapture() {
        defer { isCapturing = false }

        guard let image = captureScreen() else {
            showToast("Failed to capture screen", style: .error)
            return
        }

        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            showToast("Failed to encode image", style: .error)
            return
        }

        // Save locally first
        let filename = "screenshot_\(UUID().uuidString).jpg"
        let localURL = screenshotsDirectory.appendingPathComponent(filename)
        do {
            try imageData.write(to: localURL)
        } catch {
            showToast("Failed to save screenshot locally", style: .error)
            return
        }

        uploadImage(imageData: imageData, localFilename: filename)
    }

    private func captureScreen() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    // MARK: - Upload

    private func uploadImage(imageData: Data, localFilename: String) {
        guard let url = URL(string: uploadURL) else { return }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        let currentApiKey = apiKey
        let currentUsername = basicAuthUsername
        let currentPassword = basicAuthPassword

        if !currentUsername.isEmpty {
            let credentials = "\(currentUsername):\(currentPassword)"
            if let data = credentials.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        } else if !currentApiKey.isEmpty {
            request.setValue(currentApiKey, forHTTPHeaderField: apiKeyHeader)
        }

        var body = Data()
        let filename = "screenshot_\(Int(Date().timeIntervalSince1970)).jpg"

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showToast("Upload failed: \(error.localizedDescription)", style: .error)
                    self?.cleanupLocalFile(localFilename)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.showToast("Upload failed: invalid response", style: .error)
                    self?.cleanupLocalFile(localFilename)
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    self?.showToast("Upload failed: HTTP \(httpResponse.statusCode)", style: .error)
                    self?.cleanupLocalFile(localFilename)
                    return
                }

                guard let data = data else {
                    self?.showToast("Upload failed: no response data", style: .error)
                    self?.cleanupLocalFile(localFilename)
                    return
                }

                self?.parseResponseAndSave(data, localFilename: localFilename)
            }
        }.resume()
    }

    private func parseResponseAndSave(_ data: Data, localFilename: String) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            showToast("Upload failed: could not parse response", style: .error)
            cleanupLocalFile(localFilename)
            return
        }

        guard let resolved = resolveJSONKeyPath(responseURLKeyPath, in: json) else {
            showToast("Key '\(responseURLKeyPath)' not found in response", style: .error)
            cleanupLocalFile(localFilename)
            return
        }

        guard let publicURL = resolved as? String else {
            showToast("Upload failed: URL value is not a string", style: .error)
            cleanupLocalFile(localFilename)
            return
        }

        // Success — save entry and copy to clipboard
        let entry = ScreenshotEntry(
            id: UUID(),
            timestamp: Date(),
            publicURL: publicURL,
            localImageFilename: localFilename
        )
        screenshots.insert(entry, at: 0)

        // Enforce max screenshot limit
        while screenshots.count > Self.maxScreenshots {
            let removed = screenshots.removeLast()
            cleanupLocalFile(removed.localImageFilename)
        }

        saveHistory()

        UIPasteboard.general.string = publicURL
        showToast("URL copied to clipboard", style: .success)
    }

    // MARK: - Public Methods (Screenshots Tab)

    func deleteScreenshot(_ entry: ScreenshotEntry) {
        screenshots.removeAll { $0.id == entry.id }
        cleanupLocalFile(entry.localImageFilename)
        saveHistory()
    }

    func deleteAllScreenshots() {
        for entry in screenshots {
            cleanupLocalFile(entry.localImageFilename)
        }
        screenshots.removeAll()
        saveHistory()
    }

    func copyURL(_ entry: ScreenshotEntry) {
        UIPasteboard.general.string = entry.publicURL
        showToast("URL copied to clipboard", style: .success)
    }

    func loadImage(for entry: ScreenshotEntry) -> UIImage? {
        let url = screenshotsDirectory.appendingPathComponent(entry.localImageFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Persistence

    private func ensureScreenshotsDirectory() {
        try? FileManager.default.createDirectory(
            at: screenshotsDirectory,
            withIntermediateDirectories: true
        )
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyFileURL),
              let entries = try? JSONDecoder().decode([ScreenshotEntry].self, from: data)
        else { return }
        screenshots = entries
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(screenshots) else { return }
        try? data.write(to: historyFileURL)
    }

    private func cleanupLocalFile(_ filename: String) {
        let url = screenshotsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Toast

    private func showToast(_ message: String, style: ToastStyle) {
        let newToast = ToastMessage(message: message, style: style)
        let toastId = newToast.id

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toast = newToast
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if self.toast?.id == toastId {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.toast = nil
                }
            }
        }
    }
}

// MARK: - Data Extension

extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
