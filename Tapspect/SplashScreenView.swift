import SwiftUI

struct SplashScreenView: View {
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var spinnerOpacity: Double = 0
    @State private var spinnerRotation: Double = 0
    @State private var breatheScale: CGFloat = 1.0
    @State private var glowScale: CGFloat = 1.0

    private let brandBlue = Color(red: 0.231, green: 0.510, blue: 0.965)   // #3B82F6
    private let brandIndigo = Color(red: 0.388, green: 0.400, blue: 0.945) // #6366F1

    var body: some View {
        ZStack {
            Color(white: 0.06)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    // Radial glow behind icon
                    RadialGradient(
                        colors: [brandBlue.opacity(0.4), brandIndigo.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 120
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(glowScale)
                    .opacity(glowOpacity)

                    // App icon
                    Image("SplashIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 26.8, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                }
                .scaleEffect(logoScale * breatheScale)
                .opacity(logoOpacity)

                // App title
                Text("Tapspect")
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [brandBlue, brandIndigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(titleOpacity)

                // Spinner
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        AngularGradient(
                            colors: [brandBlue, brandIndigo, brandBlue.opacity(0.1)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(spinnerRotation))
                    .opacity(spinnerOpacity)
            }
        }
        .onAppear {
            // Phase 1: Logo entrance (0–0.6s)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            // Phase 2: Glow + title (0.5–1.0s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    glowOpacity = 1.0
                    titleOpacity = 1.0
                }
            }

            // Phase 3: Breathing animation (0.6s+)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    breatheScale = 1.02
                    glowScale = 1.08
                }
            }

            // Phase 4: Spinner (0.8s+)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.3)) {
                    spinnerOpacity = 1.0
                }
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    spinnerRotation = 360
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
