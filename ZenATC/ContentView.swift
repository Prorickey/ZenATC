//
//  ContentView.swift
//  ZenATC
//

import SwiftUI

struct ContentView: View {
    let authManager: AuthManager
    let purchaseManager: PurchaseManager
    @State private var audio = AudioManager()
    @State private var themeManager = ThemeManager()
    @State private var showTrackPicker = false
    @State private var showSettings = false
    @State private var showUpgrade = false
    @State private var showAirports = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let airports = Airport.all
    private let tracks = LofiTrack.all

    var body: some View {
        @Bindable var audio = audio

        ZStack(alignment: .top) {
            themeManager.theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TopBarView(showSettings: $showSettings, showAirports: $showAirports)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                Spacer().frame(height: 20)

                AirportCarouselView(
                    airports: airports,
                    currentIndex: $audio.currentAirportIndex
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .onChange(of: audio.currentAirportIndex) { audio.reloadATC() }

                BottomControlsView(
                    balance: $audio.balance,
                    isPlaying: $audio.isPlaying,
                    tracks: tracks,
                    selectedTrackIndex: $audio.selectedTrackIndex,
                    showTrackPicker: $showTrackPicker
                )
                .onChange(of: audio.selectedTrackIndex) { audio.reloadLofi() }
            }

            SettingsView(
                authManager: authManager,
                purchaseManager: purchaseManager,
                showSettings: $showSettings,
                showUpgrade: $showUpgrade,
                currentAirportIndex: $audio.currentAirportIndex
            )
            .offset(y: showSettings ? 0 : 1000)
            .opacity(showSettings ? 1 : 0)
            .allowsHitTesting(showSettings)
            .zIndex(3)

            if showUpgrade {
                UpgradeView(
                    authManager: authManager,
                    purchaseManager: purchaseManager,
                    showUpgrade: $showUpgrade
                )
                .transition(.move(edge: .bottom))
                .zIndex(4)
            }

            if showAirports {
                AirportsListView(
                    showAirports: $showAirports,
                    currentAirportIndex: $audio.currentAirportIndex,
                    showUpgrade: $showUpgrade
                )
                .transition(.move(edge: .top))
                .zIndex(2)
            }

            if !hasCompletedOnboarding {
                OnboardingView(isCompleted: $hasCompletedOnboarding, audio: audio)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .onAppear { hasCompletedOnboarding = false }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showSettings)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showUpgrade)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showAirports)
        .animation(.easeInOut(duration: 0.6), value: hasCompletedOnboarding)
        .environment(themeManager)
    }
}

// MARK: - Top Bar

private struct TopBarView: View {
    @Binding var showSettings: Bool
    @Binding var showAirports: Bool
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 10) {
            LiveIndicatorView()

            Text("LIVE")
                .font(.gtStandard(size: 18))
                .fontWeight(.semibold)
                .foregroundStyle(themeManager.theme.foreground)

            Spacer()

            RightIconsView(showSettings: $showSettings, showAirports: $showAirports)
        }
    }
}

// MARK: - Live Indicator

private struct LiveIndicatorView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(themeManager.theme.foreground.opacity(0.5))
                .frame(width: 32, height: 32)
                .scaleEffect(isPulsing ? 1.15 : 0.85)
                .opacity(isPulsing ? 0.3 : 0.5)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Circle()
                .fill(themeManager.theme.foreground)
                .frame(width: 14, height: 14)
        }
        .onAppear { isPulsing = true }
    }
}

// MARK: - Right Icons

private struct RightIconsView: View {
    @Binding var showSettings: Bool
    @Binding var showAirports: Bool
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 24) {
            Button {
                showAirports = true
            } label: {
                Image(systemName: "airplane")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    themeManager.cycleTheme()
                }
            } label: {
                Image(systemName: "paintpalette.fill")
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
        }
        .font(.system(size: 28))
        .foregroundStyle(themeManager.theme.foreground)
        .buttonStyle(.plain)
    }
}

// MARK: - Airport Carousel

private struct AirportCarouselView: View {
    let airports: [Airport]
    @Binding var currentIndex: Int

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(airports.indices, id: \.self) { index in
                AirportPageView(airport: airports[index])
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

private struct AirportPageView: View {
    let airport: Airport
    @Environment(ThemeManager.self) private var themeManager
    @State private var naturalTextWidth: CGFloat = 0

    private let referenceCapHeight: CGFloat = UIFont.gtStandardAirport(size: 200).capHeight

    var body: some View {
        GeometryReader { geo in
            let scaleX = naturalTextWidth > 0 ? geo.size.width / naturalTextWidth - 0.05 : 1
            let scaleY = referenceCapHeight > 0 ? geo.size.height / referenceCapHeight - 0.15 : 1

            Text(airport.code.uppercased())
                .font(.gtStandardAirport(size: 200))
                .kerning(0)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(themeManager.theme.foreground)
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear {
                            if naturalTextWidth == 0 {
                                naturalTextWidth = proxy.size.width
                            }
                        }
                    }
                )
                .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .opacity(naturalTextWidth == 0 ? 0 : 1)
        }
    }
}

// MARK: - Bottom Controls

private struct BottomControlsView: View {
    @Binding var balance: Double
    @Binding var isPlaying: Bool
    let tracks: [LofiTrack]
    @Binding var selectedTrackIndex: Int
    @Binding var showTrackPicker: Bool
    @Environment(ThemeManager.self) private var themeManager
    var body: some View {
        VStack(spacing: 0) {
            MixerSliderView(balance: $balance)
                .padding(.horizontal, 20)

            PlayPauseButton(isPlaying: $isPlaying)
                .padding(.top, 16)

            // Picker and title share a fixed-height ZStack so no layout animation
            // competes with drag tracking. Visual transforms only.
            ZStack {
                InlineTrackPicker(
                    tracks: tracks,
                    selectedIndex: $selectedTrackIndex,
                    isExpanded: showTrackPicker,
                    onConfirm: {
                        withAnimation(.spring(duration: 0.45)) {
                            showTrackPicker = false
                        }
                    }
                )
                .allowsHitTesting(showTrackPicker)
                .opacity(showTrackPicker ? 1 : 0)

                Button {
                    withAnimation(.spring(duration: 0.45)) {
                        showTrackPicker = true
                    }
                } label: {
                    Text(tracks[selectedTrackIndex].name)
                        .font(.system(size: 34.77, weight: .semibold))
                        .kerning(0)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(themeManager.theme.foreground)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .allowsHitTesting(!showTrackPicker)
                .opacity(showTrackPicker ? 0 : 1)
                .offset(y: showTrackPicker ? -20 : 0)
            }
            .padding(.top, 16)
            .padding(.bottom, 36)
            .animation(.spring(duration: 0.4), value: showTrackPicker)
        }
        .padding(.top, 10)
    }
}

// MARK: - Inline Track Picker (custom wheel)

private struct InlineTrackPicker: View {
    let tracks: [LofiTrack]
    @Binding var selectedIndex: Int
    let isExpanded: Bool
    let onConfirm: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    private let itemHeight: CGFloat = 52
    private let visibleCount = 3
    @State private var dragOffset: CGFloat = 0
    @State private var textWidths: [Int: CGFloat] = [:]

    private func centredIndex(drag: CGFloat) -> Int {
        let raw = Double(selectedIndex) - Double(drag) / Double(itemHeight)
        return max(0, min(Int(round(raw)), tracks.count - 1))
    }

    var body: some View {
        let totalHeight = itemHeight * CGFloat(visibleCount)
        let baseOffset = totalHeight / 2 - itemHeight / 2 - CGFloat(selectedIndex) * itemHeight
        let rawCenter = Double(selectedIndex) - Double(dragOffset) / Double(itemHeight)

        GeometryReader { geo in
            let availableWidth = geo.size.width - 32

            VStack(spacing: 0) {
                ForEach(tracks.indices, id: \.self) { i in
                    let dist = abs(Double(i) - rawCenter)
                    let size = CGFloat(28) + CGFloat(max(0, 1 - dist)) * 6.77
                    let opacity = max(0.15, 1.0 - dist * 0.55)
                    let fits = (textWidths[i] ?? 0) <= availableWidth
                    let isSelected = i == selectedIndex

                    Text(tracks[i].name)
                        .font(.system(size: isSelected ? 34.77 : size, weight: dist < 0.5 ? .semibold : .regular))
                        .foregroundStyle(themeManager.theme.foreground.opacity(opacity))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: TextWidthKey.self, value: [i: proxy.size.width])
                            }
                        )
                        .frame(height: fits ? itemHeight : 0)
                        .frame(maxWidth: .infinity)
                        .opacity(fits ? (isSelected ? 1 : (isExpanded ? 1 : 0)) : 0)
                        .animation(.easeInOut(duration: 0.25).delay(isSelected ? 0 : 0.12), value: isExpanded)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if i == selectedIndex && dragOffset == 0 {
                                onConfirm()
                            } else {
                                withAnimation(.spring(duration: 0.3)) {
                                    selectedIndex = i
                                    dragOffset = 0
                                }
                            }
                        }
                }
            }
            .offset(y: baseOffset + dragOffset)
            .onPreferenceChange(TextWidthKey.self) { value in
                textWidths.merge(value) { _, new in new }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    withAnimation(.none) {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    let newIndex = centredIndex(drag: value.predictedEndTranslation.height)
                    withAnimation(.spring(duration: 0.3)) {
                        selectedIndex = newIndex
                        dragOffset = 0
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: selectedIndex)
        .frame(height: totalHeight)
        .clipped()
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Mixer Slider

private struct MixerSliderView: View {
    @Binding var balance: Double
    @Environment(ThemeManager.self) private var themeManager
    @State private var isDragging = false
    @State private var hasMoved = false

    var body: some View {
        GeometryReader { geo in
            let scale: CGFloat = 1.5
            let trackHeight: CGFloat = (isDragging ? 36 : 29) * scale
            let thumbWidth: CGFloat = (isDragging ? 66 : 62) * scale
            let thumbHeight: CGFloat = (isDragging ? 28 : 24) * scale
            let trackInset: CGFloat = 2 * scale
            let iconInset: CGFloat = 14 * scale
            let iconFrame: CGFloat = 20 * scale

            let usableRange = max(geo.size.width - (trackInset * 2) - thumbWidth, 1)
            let baseThumbLeft = trackInset + CGFloat(balance) * usableRange
            let baseThumbRight = baseThumbLeft + thumbWidth
            let endClipWidth = iconInset + iconFrame
            let endZone: CGFloat = 10 * scale
            let leftDistance = max(baseThumbLeft - trackInset, 0)
            let rightDistance = max((geo.size.width - trackInset) - baseThumbRight, 0)
            let leftProgress = max(0, min((endZone - leftDistance) / endZone, 1))
            let rightProgress = max(0, min((endZone - rightDistance) / endZone, 1))
            let endProgress = max(leftProgress, rightProgress)
            let smoothProgress = endProgress * endProgress * (3 - 2 * endProgress)
            let clipWidth = thumbWidth - (thumbWidth - endClipWidth) * smoothProgress
            let leftIconCenter = iconInset + (iconFrame / 2)
            let rightIconCenter = geo.size.width - iconInset - (iconFrame / 2)
            let targetCenter = rightProgress > leftProgress ? rightIconCenter : leftIconCenter
            let baseCenter = baseThumbLeft + (thumbWidth / 2)
            let desiredCenter = baseCenter + (targetCenter - baseCenter) * smoothProgress
            let thumbX = desiredCenter - (thumbWidth / 2)
            let bumpScale = 1 + 0.04 * smoothProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(themeManager.theme.foreground.opacity(0.2))
                    .frame(height: trackHeight)

                // Base icons in fg — drawn before the pill so they show outside it
                Image(systemName: "headphones")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(themeManager.theme.foreground)
                    .frame(width: iconFrame)
                    .offset(x: iconInset)

                Image(systemName: "airplane")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(themeManager.theme.foreground)
                    .frame(width: iconFrame)
                    .offset(x: geo.size.width - iconInset - iconFrame)

                // Pill
                Capsule()
                    .fill(themeManager.theme.foreground)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .mask(alignment: .center) {
                        RoundedRectangle(cornerRadius: thumbHeight / 2)
                            .frame(width: clipWidth, height: thumbHeight)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
                            .animation(.easeOut(duration: 0.40), value: smoothProgress)
                    }
                    .scaleEffect(x: 1, y: bumpScale, anchor: .center)
                    .offset(x: thumbX)

                // White icons masked to the pill shape — visible only where pill covers them
                ZStack(alignment: .leading) {
                    Color.clear

                    Image(systemName: "headphones")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .opacity(0.65)
                        .frame(width: iconFrame)
                        .offset(x: iconInset)

                    Image(systemName: "airplane")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .opacity(0.65)
                        .frame(width: iconFrame)
                        .offset(x: geo.size.width - iconInset - iconFrame)
                }
                .mask(alignment: .leading) {
                    Capsule()
                        .frame(width: thumbWidth, height: thumbHeight)
                        .mask(alignment: .center) {
                            RoundedRectangle(cornerRadius: thumbHeight / 2)
                                .frame(width: clipWidth, height: thumbHeight)
                                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
                                .animation(.easeOut(duration: 0.40), value: smoothProgress)
                        }
                        .scaleEffect(x: 1, y: bumpScale, anchor: .center)
                        .offset(x: thumbX)
                }
            }
            .frame(height: 36 * scale, alignment: .center)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.40), value: smoothProgress)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        if !hasMoved {
                            let distance = hypot(value.translation.width, value.translation.height)
                            if distance > 6 { hasMoved = true }
                        }
                        let newValue = valueFromLocation(
                            value.location.x,
                            width: geo.size.width,
                            inset: trackInset,
                            thumbWidth: thumbWidth
                        )
                        balance = min(max(newValue, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        hasMoved = false
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        }
        .frame(height: 36 * 1.5)
    }

    private func valueFromLocation(_ x: CGFloat, width: CGFloat, inset: CGFloat, thumbWidth: CGFloat) -> Double {
        let usable = max(width - (inset * 2) - thumbWidth, 1)
        let clamped = min(max(x - inset - (thumbWidth / 2), 0), usable)
        return Double(clamped / usable)
    }
}

// MARK: - Play/Pause Button

private struct PlayPauseButton: View {
    @Binding var isPlaying: Bool
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Button {
            isPlaying.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(themeManager.theme.foreground.opacity(isPlaying ? 0.1 : 1.0))
                    .frame(width: 86.73, height: 86.73)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(isPlaying ? themeManager.theme.foreground : themeManager.theme.background)
                    .offset(x: isPlaying ? 0 : 2)
            }
        }
    }
}

#Preview {
    ContentView(authManager: AuthManager(), purchaseManager: PurchaseManager())
}
