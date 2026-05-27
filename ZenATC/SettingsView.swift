//
//  SettingsView.swift
//  ZenATC
//

import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Binding var showSettings: Bool

    private let settingsAccent = Color(red: 0.878, green: 0.298, blue: 0.149)

    private let appearanceColors: [Color] = [
        Color(red: 0.91, green: 0.28, blue: 0.16),
        Color(red: 0.12, green: 0.55, blue: 0.29),
        Color(red: 0.16, green: 0.31, blue: 0.78),
        Color(red: 0.15, green: 0.15, blue: 0.15)
    ]

    private let filters: [FilterOption] = [
        FilterOption(title: "Normal", subtitle: "Regular ATC audio", isPro: false, isSelected: true),
        FilterOption(title: "Crisp", subtitle: "Sharp ATC audio that stands out", isPro: true, isSelected: false),
        FilterOption(title: "Hallway", subtitle: "Soft and muffled. Great for sleep", isPro: true, isSelected: false)
    ]

    private let audioPacks: [AudioPack] = [
        AudioPack(title: "Cold Ice", subtitle: "Medium-energy Lo-Fi", isPro: false),
        AudioPack(title: "Cloudsurfing", subtitle: "Medium-energy Lo-Fi", isPro: false),
        AudioPack(title: "Cloudsurfing", subtitle: "Medium-energy Lo-Fi", isPro: true),
        AudioPack(title: "Airport Terminal", subtitle: "Medium-energy Lo-Fi", isPro: true),
        AudioPack(title: "Retrowave", subtitle: "Medium-energy Lo-Fi", isPro: true),
        AudioPack(title: "Thunderstorms", subtitle: "Medium-energy Lo-Fi", isPro: true),
        AudioPack(title: "Affirmations", subtitle: "Medium-energy Lo-Fi", isPro: true),
        AudioPack(title: "Caffeine", subtitle: "Medium-energy Lo-Fi", isPro: true)
    ]

    var body: some View {
        ZStack {
            themeManager.theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    appAppearance
                    upgradeCard
                    filterSection
                    airportCard
                    audioPacksSection
                    premiumAudioCard
                    joinButton
                    makeItYours
                    boringStuff
                }
                .padding(.bottom, 30)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Settings")
                .font(.system(size: 34.77, weight: .bold))
                .foregroundStyle(settingsAccent)

            Spacer()

            Button {
                showSettings = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(settingsAccent)
                    .frame(width: 42.24, height: 42.24)
                    .background(settingsAccent.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 92)
    }

    private var appAppearance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App appearance")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(settingsAccent)

            HStack(spacing: 12) {
                Circle()
                    .stroke(settingsAccent, lineWidth: 1)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Circle()
                            .fill(appearanceColors[0])
                            .frame(width: 36, height: 36)
                    )

                ForEach(appearanceColors.indices.dropFirst(), id: \.self) { index in
                    Circle()
                        .fill(appearanceColors[index])
                        .frame(width: 45.37, height: 45.37)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("7+ more in")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(settingsAccent)
                    ProBadge()
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var upgradeCard: some View {
        VStack(spacing: 14) {
            Text("Unlock more music, custom ATC audio filters, and 50 more airports")
                .font(.system(size: 19.23, weight: .medium))
                .foregroundStyle(settingsAccent)
                .multilineTextAlignment(.center)
                .frame(width: 330)

            Button {
            } label: {
                Text("Upgrade now")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(themeManager.theme.background)
                    .frame(width: 246, height: 44)
                    .background(settingsAccent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 370, height: 204)
        .background(settingsAccent.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .frame(maxWidth: .infinity)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("ATC radio filters")
                    .font(.system(size: 29.56, weight: .semibold))
                    .foregroundStyle(settingsAccent)

                Text("PRO")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(themeManager.theme.background)
                    .frame(width: 42.51, height: 23.51)
                    .background(settingsAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 5.91))
            }

            VStack(spacing: 12) {
                ForEach(filters) { filter in
                    FilterRow(filter: filter, accent: settingsAccent)
                }

                HStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Text("Try it")
                            .font(.system(size: 20.95, weight: .semibold))
                            .foregroundStyle(settingsAccent)

                        RoundedRectangle(cornerRadius: 21.11)
                            .stroke(settingsAccent, lineWidth: 1)
                            .frame(width: 54.9, height: 41.7)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var airportCard: some View {
        VStack(spacing: 8) {
            Text("50")
                .font(.gtStandardAirport(size: 100))
                .fontWeight(.semibold)
                .foregroundStyle(themeManager.theme.foreground)

            HStack(spacing: 6) {
                Text("PRO")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(themeManager.theme.background)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(themeManager.theme.foreground)
                    .clipShape(Capsule())

                Text("airports")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(themeManager.theme.foreground)
            }

            Button {
            } label: {
                Text("See the list")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeManager.theme.foreground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(themeManager.theme.foreground.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(themeManager.theme.foreground.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20)
    }

    private var audioPacksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Audio packs")
                Text("Select up to 3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(themeManager.theme.foreground.opacity(0.7))
            }

            VStack(spacing: 10) {
                ForEach(audioPacks) { pack in
                    AudioPackRow(pack: pack)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var premiumAudioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                sectionTitle("Premium Audio")
                ProBadge()
            }

            Text("Professionally produced spatial audio for relaxation and focus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(themeManager.theme.foreground.opacity(0.7))

            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(themeManager.theme.foreground.opacity(0.4), lineWidth: 1)
                        .frame(width: 60, height: 28)
                }
            }
            .padding(.top, 6)
        }
        .padding(16)
        .background(themeManager.theme.foreground.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20)
    }

    private var joinButton: some View {
        HStack {
            Spacer()
            Button {
            } label: {
                HStack(spacing: 6) {
                    Text("Join")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(themeManager.theme.background)
                    ProBadge(inverted: true)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(themeManager.theme.foreground)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var makeItYours: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Make it your own")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(themeManager.theme.foreground.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    AirportCard(code: "JFK", style: .green)
                    AirportCard(code: "SFO", style: .orange)
                    AirportCard(code: "LAX", style: .blue)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var boringStuff: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Boring stuff")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(themeManager.theme.foreground.opacity(0.6))

            VStack(alignment: .leading, spacing: 6) {
                Text("Restore")
                Text("Terms of Service")
                Text("Support")
                Text("Privacy Policy")
                Text("Cancel")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(themeManager.theme.foreground.opacity(0.7))
        }
        .padding(.horizontal, 20)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(themeManager.theme.foreground)
    }
}

private struct ProBadge: View {
    @Environment(ThemeManager.self) private var themeManager
    var inverted = false

    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(inverted ? themeManager.theme.foreground : themeManager.theme.background)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(inverted ? themeManager.theme.background : themeManager.theme.foreground)
            .clipShape(Capsule())
    }
}

private struct FilterOption: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let isPro: Bool
    let isSelected: Bool
}

private struct FilterRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let filter: FilterOption
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(filter.isSelected ? accent : accent.opacity(0.25))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(filter.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                    if filter.isPro {
                        ProBadge()
                    }
                }
                Text(filter.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent.opacity(0.75))
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent)
        }
        .frame(height: filter.isSelected ? 70 : 69)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .stroke(accent.opacity(0.2), lineWidth: filter.isSelected ? 0 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(accent.opacity(filter.isSelected ? 0.15 : 0.08))
                )
        )
    }
}

private struct AudioPack: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let isPro: Bool
}

private struct AudioPackRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let pack: AudioPack

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(themeManager.theme.foreground.opacity(0.15))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pack.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(themeManager.theme.foreground)
                    if pack.isPro {
                        ProBadge()
                    }
                }
                Text(pack.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(themeManager.theme.foreground.opacity(0.6))
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(themeManager.theme.background)
                .frame(width: 22, height: 22)
                .background(themeManager.theme.foreground)
                .clipShape(Circle())
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(themeManager.theme.foreground.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private enum AirportCardStyle {
    case green
    case orange
    case blue

    func colors() -> (Color, Color) {
        switch self {
        case .green:
            return (Color(red: 0.13, green: 0.52, blue: 0.29), Color(red: 0.78, green: 0.9, blue: 0.68))
        case .orange:
            return (Color(red: 0.94, green: 0.46, blue: 0.16), Color(red: 0.98, green: 0.86, blue: 0.68))
        case .blue:
            return (Color(red: 0.15, green: 0.4, blue: 0.74), Color(red: 0.78, green: 0.9, blue: 0.98))
        }
    }
}

private struct AirportCard: View {
    let code: String
    let style: AirportCardStyle

    var body: some View {
        let colors = style.colors()
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(colors.1)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colors.0.opacity(0.2), lineWidth: 1)
                )

            Text(code)
                .font(.gtStandardAirport(size: 56))
                .foregroundStyle(colors.0)
        }
        .frame(width: 120, height: 170)
    }
}

#Preview {
    @Previewable @State var show = true
    SettingsView(showSettings: $show)
        .environment(ThemeManager())
}
