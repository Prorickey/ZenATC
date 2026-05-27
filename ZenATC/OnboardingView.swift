//
//  OnboardingView.swift
//  ZenATC
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isCompleted: Bool
    var audio: AudioManager
    @Environment(ThemeManager.self) private var themeManager

    @State private var step = 0

    var body: some View {
        ZStack {
            themeManager.theme.background.ignoresSafeArea()

            if step == 0 {
                SplashStep()
                    .transition(.opacity)
            } else if step == 1 {
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
                    removal:   .move(edge: .leading)
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
                    removal:   .move(edge: .leading)
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
                    removal:   .move(edge: .leading)
                ))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                step = 1
            }
        }
    }
}

// MARK: - Splash

private struct SplashStep: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var naturalTextWidth: CGFloat = 0

    private let referenceCapHeight: CGFloat = UIFont.gtStandardAirport(size: 200).capHeight

    var body: some View {
        GeometryReader { geo in
            let scaleX = naturalTextWidth > 0 ? geo.size.width / naturalTextWidth - 0.05 : 1
            let scaleY = referenceCapHeight > 0 ? geo.size.height / referenceCapHeight - 0.15 : 1

            Text("lofi atc")
                .font(.gtStandardAirport(size: 200))
                .kerning(0)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(themeManager.theme.foreground)
                .background(GeometryReader { proxy in
                    Color.clear.onAppear {
                        if naturalTextWidth == 0 {
                            naturalTextWidth = proxy.size.width
                        }
                    }
                })
                .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .opacity(naturalTextWidth == 0 ? 0 : 1)
        }
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
    @State private var naturalTextWidth: CGFloat = 0

    private let referenceCapHeight: CGFloat = UIFont.gtStandardAirport(size: 200).capHeight

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let scaleX = naturalTextWidth > 0 ? geo.size.width / naturalTextWidth - 0.05 : 1
                let scaleY = referenceCapHeight > 0 ? geo.size.height / referenceCapHeight - 0.15 : 1

                Text(number)
                    .font(.gtStandardAirport(size: 200))
                    .kerning(0)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(themeManager.theme.foreground)
                    .background(GeometryReader { proxy in
                        Color.clear.onAppear {
                            if naturalTextWidth == 0 {
                                naturalTextWidth = proxy.size.width
                            }
                        }
                    })
                    .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .opacity(naturalTextWidth == 0 ? 0 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
            .padding(.bottom, 60)
        }
    }
}

#Preview {
    OnboardingView(isCompleted: .constant(false), audio: AudioManager())
        .environment(ThemeManager())
}
