//
//  OnboardingView.swift
//  ZenATC
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isCompleted: Bool
    var audio: AudioManager
    @Environment(ThemeManager.self) private var themeManager

    @State private var step = 1

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
                    audio.fadeToBalance(0)
                    audio.fadeInPlayback()
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
                    audio.fadeToBalance(0.5)
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
                .font(.gtStandardAirport(size: 400))
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
