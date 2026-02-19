import SwiftUI

@main
struct TapspectApp: App {
    @StateObject private var screenshotService = ScreenshotService()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(screenshotService)

                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation(.easeIn(duration: 0.4)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
