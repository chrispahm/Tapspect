import XCTest
@testable import Tapspect

final class URLValidationTests: XCTestCase {

    // MARK: - Valid URLs

    func testValidHTTPSURL() {
        XCTAssertTrue(isValidWebURL("https://example.com"))
    }

    func testValidHTTPURL() {
        XCTAssertTrue(isValidWebURL("http://example.com"))
    }

    func testValidURLWithPath() {
        XCTAssertTrue(isValidWebURL("https://example.com/path/to/resource"))
    }

    func testValidURLWithPort() {
        XCTAssertTrue(isValidWebURL("http://localhost:3000"))
    }

    func testValidURLWithQueryParams() {
        XCTAssertTrue(isValidWebURL("https://example.com/search?q=test&page=1"))
    }

    func testValidIPAddress() {
        XCTAssertTrue(isValidWebURL("http://192.168.1.1"))
    }

    func testValidURLWithFragment() {
        XCTAssertTrue(isValidWebURL("https://example.com/page#section"))
    }

    // MARK: - Invalid URLs

    func testEmptyString() {
        XCTAssertFalse(isValidWebURL(""))
    }

    func testPlainText() {
        XCTAssertFalse(isValidWebURL("not a url"))
    }

    func testMissingScheme() {
        XCTAssertFalse(isValidWebURL("example.com"))
    }

    func testFTPScheme() {
        XCTAssertFalse(isValidWebURL("ftp://files.example.com"))
    }

    func testFileScheme() {
        XCTAssertFalse(isValidWebURL("file:///tmp/test"))
    }

    func testSchemeOnly() {
        XCTAssertFalse(isValidWebURL("https://"))
    }

    func testJavascriptScheme() {
        XCTAssertFalse(isValidWebURL("javascript:alert(1)"))
    }

    func testDataScheme() {
        XCTAssertFalse(isValidWebURL("data:text/html,<h1>Hello</h1>"))
    }

    func testWhitespaceOnly() {
        XCTAssertFalse(isValidWebURL("   "))
    }
}

// MARK: - JSON Key Path Tests

final class JSONKeyPathTests: XCTestCase {

    func testSimpleKey() {
        let json: [String: Any] = ["url": "https://example.com/image.jpg"]
        let result = resolveJSONKeyPath("url", in: json)
        XCTAssertEqual(result as? String, "https://example.com/image.jpg")
    }

    func testNestedKeyPath() {
        let json: [String: Any] = [
            "data": ["image": ["url": "https://cdn.example.com/pic.jpg"]]
        ]
        let result = resolveJSONKeyPath("data.image.url", in: json)
        XCTAssertEqual(result as? String, "https://cdn.example.com/pic.jpg")
    }

    func testTwoLevelKeyPath() {
        let json: [String: Any] = [
            "response": ["url": "https://example.com/uploaded.jpg"]
        ]
        let result = resolveJSONKeyPath("response.url", in: json)
        XCTAssertEqual(result as? String, "https://example.com/uploaded.jpg")
    }

    func testMissingKey() {
        let json: [String: Any] = ["name": "test"]
        let result = resolveJSONKeyPath("url", in: json)
        XCTAssertNil(result)
    }

    func testMissingNestedKey() {
        let json: [String: Any] = ["data": ["name": "test"]]
        let result = resolveJSONKeyPath("data.url", in: json)
        XCTAssertNil(result)
    }

    func testMissingIntermediateKey() {
        let json: [String: Any] = ["other": "value"]
        let result = resolveJSONKeyPath("data.image.url", in: json)
        XCTAssertNil(result)
    }

    func testNonDictionaryIntermediate() {
        let json: [String: Any] = ["data": "not a dictionary"]
        let result = resolveJSONKeyPath("data.url", in: json)
        XCTAssertNil(result)
    }

    func testNumericValue() {
        let json: [String: Any] = ["count": 42]
        let result = resolveJSONKeyPath("count", in: json)
        XCTAssertEqual(result as? Int, 42)
    }

    func testEmptyJSON() {
        let json: [String: Any] = [:]
        let result = resolveJSONKeyPath("url", in: json)
        XCTAssertNil(result)
    }
}

// MARK: - Pretty JSON Tests

final class PrettyJSONTests: XCTestCase {

    func testValidJSONObject() {
        let input = #"{"b":"2","a":"1"}"#
        let result = prettyFormatJSON(input)
        // Should be pretty-printed and sorted by keys
        XCTAssertTrue(result.contains("\"a\""))
        XCTAssertTrue(result.contains("\"b\""))
        XCTAssertTrue(result.contains("\n"))
    }

    func testValidJSONArray() {
        let input = "[1,2,3]"
        let result = prettyFormatJSON(input)
        XCTAssertTrue(result.contains("\n"))
    }

    func testInvalidJSON() {
        let input = "not json at all"
        let result = prettyFormatJSON(input)
        XCTAssertEqual(result, input) // Returns original on failure
    }

    func testEmptyString() {
        let result = prettyFormatJSON("")
        XCTAssertEqual(result, "")
    }

    func testNestedJSON() {
        let input = #"{"user":{"name":"test","id":1}}"#
        let result = prettyFormatJSON(input)
        XCTAssertTrue(result.contains("\"name\""))
        XCTAssertTrue(result.contains("\"user\""))
    }
}

// MARK: - WebViewModel Log Capping Tests

final class WebViewModelTests: XCTestCase {

    func testConsoleLogAddsEntry() {
        let vm = WebViewModel()
        let expectation = XCTestExpectation(description: "Log added")

        vm.addConsoleLog(level: "info", message: "Hello")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(vm.consoleLogs.count, 1)
            XCTAssertEqual(vm.consoleLogs.first?.message, "Hello")
            XCTAssertEqual(vm.consoleLogs.first?.level, .info)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testErrorCountIncrements() {
        let vm = WebViewModel()
        let expectation = XCTestExpectation(description: "Error count incremented")

        vm.addConsoleLog(level: "error", message: "Something broke")
        vm.addConsoleLog(level: "error", message: "Another error")
        vm.addConsoleLog(level: "info", message: "Not an error")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(vm.errorCount, 2)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testUnknownLevelDefaultsToLog() {
        let vm = WebViewModel()
        let expectation = XCTestExpectation(description: "Unknown level defaults to .log")

        vm.addConsoleLog(level: "unknown_level", message: "test")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(vm.consoleLogs.first?.level, .log)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testNetworkRequestAddsEntry() {
        let vm = WebViewModel()
        let expectation = XCTestExpectation(description: "Network request added")

        vm.addNetworkRequest(method: "GET", url: "https://api.example.com/users", status: 200, duration: 0.5)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(vm.networkRequests.count, 1)
            XCTAssertEqual(vm.networkRequests.first?.method, "GET")
            XCTAssertEqual(vm.networkRequests.first?.statusCode, 200)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testConsoleLogCapping() {
        let vm = WebViewModel()
        let expectation = XCTestExpectation(description: "Logs capped")

        // Add more than maxLogEntries
        for i in 0..<(WebViewModel.maxLogEntries + 50) {
            vm.addConsoleLog(level: "log", message: "Message \(i)")
        }

        // Allow async dispatches to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            XCTAssertLessThanOrEqual(vm.consoleLogs.count, WebViewModel.maxLogEntries)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testNetworkRequestCapping() {
        let vm = WebViewModel()
        let expectation = XCTestExpectation(description: "Network requests capped")

        for i in 0..<(WebViewModel.maxNetworkEntries + 50) {
            vm.addNetworkRequest(method: "GET", url: "https://api.example.com/\(i)", status: 200, duration: 0.1)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            XCTAssertLessThanOrEqual(vm.networkRequests.count, WebViewModel.maxNetworkEntries)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }
}

// MARK: - DrawerDetent Tests

final class DrawerDetentTests: XCTestCase {

    func testMidOffset() {
        let height: CGFloat = 1000
        XCTAssertEqual(DrawerDetent.mid.offset(in: height), 550) // 55%
    }

    func testFullOffset() {
        let height: CGFloat = 1000
        XCTAssertEqual(DrawerDetent.full.offset(in: height), 150) // 15%
    }

    func testMidIsLowerThanFull() {
        let height: CGFloat = 812
        // Mid should be a larger offset (further down) than full
        XCTAssertGreaterThan(
            DrawerDetent.mid.offset(in: height),
            DrawerDetent.full.offset(in: height)
        )
    }

    func testZeroHeight() {
        XCTAssertEqual(DrawerDetent.mid.offset(in: 0), 0)
        XCTAssertEqual(DrawerDetent.full.offset(in: 0), 0)
    }

    func testAllCases() {
        XCTAssertEqual(DrawerDetent.allCases.count, 2)
    }
}

// MARK: - ScreenshotEntry Tests

final class ScreenshotEntryTests: XCTestCase {

    func testFormattedTimestamp() {
        let entry = ScreenshotEntry(
            id: UUID(),
            timestamp: Date(),
            publicURL: "https://example.com/img.jpg",
            localImageFilename: "test.jpg"
        )
        // Should return a non-empty formatted string
        XCTAssertFalse(entry.formattedTimestamp.isEmpty)
    }

    func testCodable() throws {
        let original = ScreenshotEntry(
            id: UUID(),
            timestamp: Date(),
            publicURL: "https://example.com/img.jpg",
            localImageFilename: "screenshot_123.jpg"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenshotEntry.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.publicURL, original.publicURL)
        XCTAssertEqual(decoded.localImageFilename, original.localImageFilename)
    }
}

// MARK: - NetworkRequest Model Tests

final class NetworkRequestTests: XCTestCase {

    func testMethodColors() {
        let get = NetworkRequest(method: "GET", url: "", statusCode: nil, duration: nil, timestamp: "", requestHeaders: nil, requestBody: nil, responseHeaders: nil, responseBody: nil, responseContentType: nil)
        let post = NetworkRequest(method: "POST", url: "", statusCode: nil, duration: nil, timestamp: "", requestHeaders: nil, requestBody: nil, responseHeaders: nil, responseBody: nil, responseContentType: nil)
        let delete = NetworkRequest(method: "DELETE", url: "", statusCode: nil, duration: nil, timestamp: "", requestHeaders: nil, requestBody: nil, responseHeaders: nil, responseBody: nil, responseContentType: nil)
        let unknown = NetworkRequest(method: "OPTIONS", url: "", statusCode: nil, duration: nil, timestamp: "", requestHeaders: nil, requestBody: nil, responseHeaders: nil, responseBody: nil, responseContentType: nil)

        // Each method should produce a different color (or at least not crash)
        XCTAssertNotEqual(get.methodColor, post.methodColor)
        XCTAssertNotEqual(post.methodColor, delete.methodColor)
        // OPTIONS should fall through to gray
        _ = unknown.methodColor
    }
}

// MARK: - ConsoleLog Model Tests

final class ConsoleLogTests: XCTestCase {

    func testAllLogLevels() {
        // Ensure all log levels have colors and text colors
        for level in ConsoleLog.LogLevel.allCases {
            _ = level.color
            _ = level.textColor
        }
        XCTAssertEqual(ConsoleLog.LogLevel.allCases.count, 5)
    }

    func testLogLevelRawValues() {
        XCTAssertEqual(ConsoleLog.LogLevel.log.rawValue, "log")
        XCTAssertEqual(ConsoleLog.LogLevel.info.rawValue, "info")
        XCTAssertEqual(ConsoleLog.LogLevel.warn.rawValue, "warn")
        XCTAssertEqual(ConsoleLog.LogLevel.error.rawValue, "error")
        XCTAssertEqual(ConsoleLog.LogLevel.debug.rawValue, "debug")
    }
}
