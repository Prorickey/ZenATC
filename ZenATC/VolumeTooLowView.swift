//
//  VolumeTooLowView.swift
//  ZenATC
//

import SwiftUI
import AVFoundation

@Observable
final class VolumeMonitor {
    var volume: Float
    private var observation: NSKeyValueObservation?

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        self.volume = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let new = change.newValue else { return }
            Task { @MainActor in
                self?.volume = new
            }
        }
    }

    deinit {
        observation?.invalidate()
    }
}

struct VolumeTooLowView: View {
    @Environment(ThemeManager.self) private var themeManager
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            themeManager.theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                HStack(alignment: .top, spacing: 3) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 24, weight: .semibold))
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(themeManager.theme.foreground)
                .padding(.bottom, 14)

                Text("Your\nvolume's\ntoo low")
                    .font(.abcGravity(size: 64))
                    .foregroundStyle(themeManager.theme.foreground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-22)

                Text("This app is a listening app")
                    .font(.airportCode(size: 18))
                    .fontWeight(.regular)
                    .foregroundStyle(themeManager.theme.foreground)
                    .padding(.top, 14)

                Spacer()
                Spacer()

                Button(action: onContinue) {
                    Text("Continue anyway")
                        .font(.airportCode(size: 22))
                        .fontWeight(.heavy)
                        .foregroundStyle(themeManager.theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(Capsule().fill(themeManager.theme.foreground))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
        .contentShape(Rectangle())
    }
}
