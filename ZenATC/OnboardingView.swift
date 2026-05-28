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
                    buttonLabel: "Start the lofi",
                    numberHeightFraction: 0.5,
                    numberStretchX: 2.0,
                    numberStretchY: 1.3
                ) {
                    audio.fadeToBalance(0)
                    audio.fadeInPlayback()
                    step += 1
                }
                .transition(.opacity)
            } else if step == 2 {
                NumberStep(
                    number: "2",
                    subtitle: "Now add some real,\nlive air traffic radio",
                    buttonIcon: "airplane",
                    buttonLabel: "Add in ATC",
                    numberHeightFraction: 0.5,
                    numberStretchX: 2.0,
                    numberStretchY: 1.3
                ) {
                    audio.fadeToBalance(0.5)
                    step += 1
                }
                .transition(.opacity)
            } else if step == 3 {
                NumberStep(
                    number: "3",
                    subtitle: "That's it! Focus, chill,\nor just fall asleep",
                    buttonIcon: "figure.run",
                    buttonLabel: "Let's go",
                    numberHeightFraction: 0.5,
                    numberStretchX: 2.0,
                    numberStretchY: 1.3
                ) {
                    step += 1
                }
                .transition(.opacity)
            } else if step == 4 {
                MessageStep(
                    lines: ["All the air traffic control\nyou hear is 100% live.",
                            "No recordings."]
                )
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                        isCompleted = true
                    }
                }
            }

            if showSplash {
                SplashStep()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
        .animation(.easeInOut(duration: 0.75), value: showSplash)
        .onAppear {
            // Remove the splash only after its own fade-out has finished (~1.75s).
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showSplash = false
            }
        }
    }
}

// MARK: - Splash

private struct SplashStep: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var planeProgress: CGFloat = 0
    @State private var splashOpacity: Double = 1
    @State private var sfxPlayer: AVAudioPlayer?

    private let tailLength: CGFloat = 90

    var body: some View {
        GeometryReader { geo in
            let planeY  = geo.size.height * 0.70
            let startX: CGFloat = -60
            let endX: CGFloat   = geo.size.width + 60
            let currentX  = startX + (endX - startX) * planeProgress

            ZStack {
                themeManager.theme.background.ignoresSafeArea()

                // "lofi atc" label — widened ~2.5x via the font's 'wdth' axis (50 → 125).
                Text("lofi atc")
                    .font(.airportCode(size: 88, width: 70))
                    .foregroundStyle(themeManager.theme.foreground)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Short radar-style trail — opaque at the plane, fading out behind it.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [themeManager.theme.foreground.opacity(0),
                                     themeManager.theme.foreground.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: tailLength, height: 2.5)
                    .position(x: currentX - tailLength / 2, y: planeY - 100)

                // Airplane icon
                Image(systemName: "airplane")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(themeManager.theme.foreground)
                    .position(x: currentX, y: planeY - 100)
            }
            .opacity(splashOpacity)
        }
        .onAppear {
            playSFX()
            // Plane flies fully across and off the right edge.
            withAnimation(.linear(duration: 1.3).delay(0.15)) {
                planeProgress = 1.0
            }
            // Fade the whole splash away as the plane leaves the screen.
            withAnimation(.easeIn(duration: 0.55).delay(1.2)) {
                splashOpacity = 0
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
    /// Big number height as a fraction of the screen height. ≈0.5 matches the reference.
    var numberHeightFraction: CGFloat = 0.5
    /// Glyph stretch multipliers (vector — stays crisp). 1.0 = natural.
    var numberStretchX: CGFloat = 1.0
    var numberStretchY: CGFloat = 1.0
    let onAction: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @State private var spun = false

    var body: some View {
        GeometryReader { geo in
            // Height comes from the point size; width comes from the font's
            // variable 'wdth' axis (50 = natural .. 150 = max). Both render crisp.
            let pointSize = geo.size.height * numberHeightFraction * numberStretchY
            let widthAxis = min(150, max(50, 50 * (numberStretchX / numberStretchY)))

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Big number — stretched via real font metrics so edges stay crisp.
                Text(number)
                    .font(.airportCode(size: pointSize, width: Double(widthAxis)))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(themeManager.theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .center)
                    // Bound the layout footprint to roughly the visible digit so the
                    // tall font's line box doesn't eat the vertical space (which blocked
                    // the lift). The glyph overflows this frame harmlessly (no clip).
                    .frame(height: pointSize * 0.8)
                    // "Rotate in" entrance — rotate + fade only (no scaling).
                    .rotationEffect(.degrees(spun ? 0 : -120))
                    .opacity(spun ? 1 : 0)
                    .onAppear {
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) {
                            spun = true
                        }
                    }

                Spacer(minLength: 0)

                VStack(spacing: 22) {
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
                .padding(.bottom, 70) // nudge subtitle + button up, closer to the number
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Message Step

private struct MessageStep: View {
    let lines: [String]

    @Environment(ThemeManager.self) private var themeManager
    @State private var visible = false

    var body: some View {
        VStack(spacing: 26) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(themeManager.theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(visible ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.9)) { visible = true }
        }
    }
}

#Preview {
    OnboardingView(isCompleted: .constant(false), audio: AudioManager())
        .environment(ThemeManager())
}
