//
//  OnboardingView.swift
//  ZenATC
//

import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var isCompleted: Bool
    var audio: AudioManager
    @Environment(ThemeManager.self) private var themeManager

    @State private var step = 1        // step 1 renders beneath splash from the start
    @State private var showSplash = true

    var body: some View {
        ZStack {
            themeManager.theme.background.ignoresSafeArea()

            if step == 1 {
                NumberStep(
                    number: "1",
                    subtitle: "Let's start with a chill\nmusic track",
                    buttonIcon: "play.fill",
                    buttonLabel: "Start the lofi"
                ) {
                    audio.balance = 0
                    audio.isPlaying = true
                    step += 1
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            } else if step == 2 {
                NumberStep(
                    number: "2",
                    subtitle: "Now add some real,\nlive air traffic radio",
                    buttonIcon: "airplane",
                    buttonLabel: "Add in ATC"
                ) {
                    audio.balance = 0.5
                    step += 1
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            } else if step == 3 {
                NumberStep(
                    number: "3",
                    subtitle: "That's it! Focus, chill,\nor just fall asleep",
                    buttonIcon: "figure.run",
                    buttonLabel: "Let's go"
                ) {
                    isCompleted = true
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            }

            if showSplash {
                SplashStep()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
        .animation(.easeInOut(duration: 0.75), value: showSplash)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                showSplash = false
            }
        }
    }
}

// MARK: - Splash

private struct SplashStep: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var planeProgress: CGFloat = 0
    @State private var sfxPlayer: AVAudioPlayer?

    var body: some View {
        GeometryReader { geo in
            let planeY  = geo.size.height * 0.70
            let startX: CGFloat = -44
            let endX: CGFloat   = geo.size.width + 44
            let currentX  = startX + (endX - startX) * planeProgress
            let trailWidth = max(0, min(currentX, geo.size.width))

            ZStack {
                themeManager.theme.background.ignoresSafeArea()

                // "lofi atc" label — sits just above the flight path
                Text("lofi atc")
                    .font(.airportCode(size: 88))
                    .foregroundStyle(themeManager.theme.foreground)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Fading trail — clear at the back, opaque near the plane
                if trailWidth > 0 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [themeManager.theme.foreground.opacity(0), themeManager.theme.foreground],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: trailWidth, height: 2)
                        .position(x: trailWidth / 2, y: planeY)
                }

                // Airplane icon
                Image(systemName: "airplane")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(themeManager.theme.foreground)
                    .position(x: currentX, y: planeY)
            }
        }
        .onAppear {
            playSFX()
            withAnimation(.linear(duration: 1.2).delay(0.2)) {
                planeProgress = 1.0
            }
        }
    }

    private func playSFX() {
        guard let url = Bundle.main.url(forResource: "plane_flyby", withExtension: "mp3") else { return }
        sfxPlayer = try? AVAudioPlayer(contentsOf: url)
        sfxPlayer?.play()
    }
}

// MARK: - Number Step

private struct NumberStep: View {
    let number: String
    let subtitle: String
    let buttonIcon: String
    let buttonLabel: String
    let onAction: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 28)

            Text(number)
                .font(.airportCode(size: 400))
                .lineLimit(1)
                .foregroundStyle(themeManager.theme.foreground)
                .frame(maxWidth: .infinity, alignment: .center)


            VStack(spacing: 20) {
                Text(subtitle)
                    .font(.system(size: 18, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(themeManager.theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 48)

                Button(action: onAction) {
                    HStack(spacing: 9) {
                        Image(systemName: buttonIcon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(buttonLabel)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(themeManager.theme.background)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(themeManager.theme.foreground)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 56)
        }
    }
}

#Preview {
    OnboardingView(isCompleted: .constant(false), audio: AudioManager())
        .environment(ThemeManager())
}
