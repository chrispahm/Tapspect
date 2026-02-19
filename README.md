# Tapspect — iOS Debug Shell

A minimal iOS app that wraps your web app in a `WKWebView` with a built-in **floating debug panel** for viewing console output and network requests — no Safari Web Inspector needed.

This is the ideal companion app for [Happy](https://happy.engineering/) & [ngrok](https://ngrok.com/), allowing you to review Claude/Codex generated websites on the go. Open the website in the app, and if any issues arise, just tap the floating bug button to see console logs and network activity in real time. Copy error messages or failed request details into Happy for instant debugging help from Claude.

## Features

- **🌐 Full WKWebView** — loads any URL, supports back/forward gestures
- **🪲 Draggable FAB** — floating debug button that snaps to screen edges
- **📋 Console tab** — captures `console.log/info/warn/error/debug`, uncaught errors, and unhandled promise rejections
- **🌍 Network tab** — intercepts `fetch()` and `XMLHttpRequest` calls with method, status, timing as well as request and reponse values
- **↕️ Resizable panel** — drag the handle to resize the debug sheet
- **🔴 Error badge** — shows error count on the FAB when panel is closed

## Quick Start

1. **Open** `Tapspect.xcodeproj` in Xcode
2. **Optional: Edit the default URL** in `ContentView.swift`:
   ```swift
   static let webAppURL = "https://your-app.example.com"
   ```
3. **Select your device** (or simulator) and hit **Run** (⌘R)
4. Tap the 🪲 **bug button** to open the debug panel

## How It Works

JavaScript is injected at document start that:

- **Overrides** `console.log/info/warn/error/debug` to forward messages to Swift via `WKScriptMessageHandler`
- **Wraps** `window.fetch()` and `XMLHttpRequest.prototype.open/send` to capture request method, URL, status code, and duration
- **Listens** for `error` and `unhandledrejection` window events

All data flows through `WebViewModel` (an `ObservableObject`) to the SwiftUI debug panel.

## Requirements

- Xcode 15+
- iOS 26.0+
- Swift 5.9+

## Notes

- `webView.isInspectable = true` is set, so Safari Web Inspector also works in debug builds
- The network interceptor captures **JavaScript-initiated** requests. Navigation-level requests (page loads, iframes) are logged via `WKNavigationDelegate`
- For localhost testing, use your Mac's local IP (e.g., `http://192.168.1.x:3000`) since the simulator/device can't reach `localhost` on your Mac directly (simulator can, physical device cannot)
