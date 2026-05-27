//
//  SettingsView.swift
//  ZenATC
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AuthManager.self) private var authManager
    @Environment(PurchaseManager.self) private var purchaseManager
    @Binding var showSettings: Bool
    @State private var showAuthSheet = false

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
        .sheet(isPresented: $showAuthSheet) {
            UpgradeFlowSheet(authManager: authManager, purchaseManager: purchaseManager)
        }
    }

    private func handleUpgradeTap() {
        guard !purchaseManager.isPro else { return }
        showAuthSheet = true
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
        .padding(.top, 20)
    }

    private var appAppearance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App appearance")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(settingsAccent)

            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    let theme = AppTheme.all[index]
                    let isSelected = themeManager.currentIndex == index

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            themeManager.setTheme(index)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(settingsAccent, lineWidth: 1.5)
                                .frame(width: 52, height: 52)
                                .opacity(isSelected ? 1 : 0)

                            Circle()
                                .fill(theme.background)
                                .frame(width: isSelected ? 40 : 46, height: isSelected ? 40 : 46)

                            Circle()
                                .fill(theme.foreground)
                                .frame(width: isSelected ? 18 : 20, height: isSelected ? 18 : 20)
                        }
                        .frame(width: 52, height: 52)
                        .animation(.easeInOut(duration: 0.2), value: isSelected)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    Text("+ 7 more in")
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
                handleUpgradeTap()
            } label: {
                Text("Upgrade now")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(themeManager.theme.background)
                    .frame(width: 200, height: 60)
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
        VStack(alignment: .leading, spacing: 23) {
            HStack(spacing: 8.5) {
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

            VStack(spacing: 11) {
                ForEach(filters) { filter in
                    FilterRow(filter: filter, accent: settingsAccent)
                }

                HStack {
                    Spacer()
                    Text("Try it")
                        .font(.system(size: 20.95, weight: .semibold))
                        .foregroundStyle(settingsAccent)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(settingsAccent)
                        .rotationEffect(.degrees(-20))
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 21.5)
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
        PremiumAudioCard(accent: settingsAccent)
            .padding(.horizontal, 20)
    }

    private var joinButton: some View {
        HStack {
            Spacer()
            Button {
                handleUpgradeTap()
            } label: {
                HStack(spacing: 6) {
                    Text("Join")
                        .font(.system(size: 30, weight: .semibold))
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Make it your own")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(settingsAccent)
                .padding(.horizontal, 20)

            ThemeCarousel(accent: settingsAccent, interval: 3.0)
        }
    }

    private var boringStuff: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Boring stuff")
                .font(.system(size: 29.56, weight: .bold))
                .foregroundStyle(settingsAccent)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Switch billing cycle")
                    Text("Restore")
                    Text("Cancel")
                }
                Spacer()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Terms of Service")
                    Text("Support")
                    Text("Privacy Policy")
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(settingsAccent)
        }
        .padding(12)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(inverted ? themeManager.theme.foreground : themeManager.theme.background)
            .padding(.horizontal, 10)
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
            // Radio indicator
            Circle()
                .strokeBorder(
                    filter.isSelected ? Color.white : accent.opacity(0.3),
                    lineWidth: filter.isSelected ? 2 : 1.5
                )
                .background(Circle().fill(filter.isSelected ? Color.clear : accent.opacity(0.12)))
                .frame(width: filter.isSelected ? 28 : 22, height: filter.isSelected ? 28 : 22)

            // Labels
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(filter.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(filter.isSelected ? .white : accent)
                    if filter.isPro {
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(filter.isSelected ? accent : .white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(filter.isSelected ? Color.white : accent)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(filter.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(filter.isSelected ? .white.opacity(0.85) : accent.opacity(0.65))
            }

            Spacer()

            // Play button
            Circle()
                .fill(filter.isSelected ? Color.white : accent)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(filter.isSelected ? accent : Color.white)
                        .offset(x: 1.5)
                )
        }
        .frame(height: filter.isSelected ? 70 : 69)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(filter.isSelected ? accent : accent.opacity(0.08))
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

private struct PremiumAudioCard: View {
    let accent: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Card background
            RoundedRectangle(cornerRadius: 20)
                .fill(accent.opacity(0.1))

            VStack(alignment: .leading, spacing: 0) {
                // Header text
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Premium Audio")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(accent)
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    Text("Professionally produced spatial audio for\nrelaxation and focus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent.opacity(0.8))
                        .lineSpacing(2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

                // Image area
                ZStack {
                    // Spirals use multiply blend to knock out white on card bg
                    VStack(spacing: 120) {
                        Image("spiral_top")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .blendMode(.multiply)

                        Image("spiral_bottom")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .blendMode(.multiply)
                    }
                    .padding(.horizontal, 4)

                    // Boy centered over the spirals
                    Image("boy")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200)
                }
                .padding(.bottom, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Theme Carousel

private struct ThemeCarousel: View {
    let accent: Color
    let interval: Double

    @State private var currentIndex = 0
    @State private var autoTimer: Timer?

    private let airports = ["LAX", "JFK", "SFO", "ORD", "LHR", "LGA"]

    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $currentIndex) {
                ForEach(AppTheme.all.indices, id: \.self) { index in
                    MiniAppScreen(
                        theme: AppTheme.all[index],
                        airportCode: airports[index % airports.count]
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 454)

            HStack(spacing: 6) {
                ForEach(AppTheme.all.indices, id: \.self) { index in
                    Capsule()
                        .fill(accent.opacity(index == currentIndex ? 1 : 0.3))
                        .frame(width: index == currentIndex ? 18 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.25), value: currentIndex)
                }
            }
        }
        .onAppear {
            autoTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentIndex = (currentIndex + 1) % AppTheme.all.count
                }
            }
        }
        .onDisappear { autoTimer?.invalidate() }
    }
}

// MARK: - Mini App Screen

private struct MiniAppScreen: View {
    let theme: AppTheme
    let airportCode: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 31.69)
                .fill(theme.background)

            VStack(spacing: 0) {
                // Top bar
                HStack(spacing: 6) {
                    Circle()
                        .fill(theme.foreground)
                        .frame(width: 7, height: 7)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.foreground)
                    Spacer()
                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(theme.foreground)
                                .frame(width: 9, height: 9)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)

                // Airport code
                Spacer()
                Text(airportCode)
                    .font(.gtStandardAirport(size: 90))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 8)
                Spacer()

                // Bottom controls
                VStack(spacing: 10) {
                    // Mixer slider
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.foreground.opacity(0.2))
                            .frame(height: 7)
                        Capsule()
                            .fill(theme.foreground)
                            .frame(width: 28, height: 5)
                            .padding(.leading, 2)
                    }
                    .padding(.horizontal, 18)

                    // Play button
                    Circle()
                        .fill(theme.foreground.opacity(0.15))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.foreground)
                                .offset(x: 1)
                        )

                    // Track name
                    Capsule()
                        .fill(theme.foreground.opacity(0.25))
                        .frame(width: 72, height: 5)
                }
                .padding(.bottom, 28)
            }
        }
        .frame(width: 208.82, height: 454)
    }
}

// MARK: - Upgrade Flow Sheet

private struct UpgradeFlowSheet: View {
    let authManager: AuthManager
    let purchaseManager: PurchaseManager

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                if !authManager.isSignedIn {
                    signInSection
                } else if !purchaseManager.isPro {
                    accountSection
                    plansSection
                } else {
                    proSection
                }
            }
            .navigationTitle("ZenATC Pro")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var signInSection: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            SecureField("Password", text: $password)
                .textContentType(.password)

            if let error = errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            Button {
                Task { await signIn() }
            } label: {
                label("Sign In")
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)

            Button {
                Task { await createAccount() }
            } label: {
                label("Create Account")
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
        } header: {
            Text("Sign in to upgrade")
        }
    }

    private var accountSection: some View {
        Section {
            Text(authManager.userEmail ?? "").foregroundStyle(.secondary)
        } header: {
            Text("Signed in as")
        }
    }

    private var plansSection: some View {
        Section {
            ForEach(purchaseManager.products) { product in
                Button {
                    Task { await purchase(product) }
                } label: {
                    HStack {
                        Text(product.displayName)
                        Spacer()
                        Text(product.displayPrice).foregroundStyle(.secondary)
                    }
                }
                .disabled(isLoading)
            }

            if let error = errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        } header: {
            Text("Choose a plan")
        }
    }

    private var proSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text("Pro ✓").foregroundStyle(.secondary)
            }
            Text(authManager.userEmail ?? "").foregroundStyle(.secondary)
            Button(role: .destructive) {
                try? authManager.signOut()
            } label: {
                Text("Sign Out")
            }
        } header: {
            Text("Account")
        }
    }

    private func label(_ title: String) -> some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text(title).frame(maxWidth: .infinity)
            }
        }
    }

    private func signIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createAccount() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.createAccount(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func purchase(_ product: Product) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await purchaseManager.purchase(product)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    @Previewable @State var show = true
    SettingsView(showSettings: $show)
        .environment(ThemeManager())
}
