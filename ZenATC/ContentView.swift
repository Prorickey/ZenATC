//
//  ContentView.swift
//  ZenATC
//

import SwiftUI

struct ContentView: View {
    @State private var audio = AudioManager()
    @State private var themeManager = ThemeManager()
    @State private var showTrackPicker = false
    @State private var showAccountSheet = false

    private let airports = Airport.all
    private let tracks = LofiTrack.all

    var body: some View {
        @Bindable var audio = audio

        ZStack {
            themeManager.theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TopBarView(showAccountSheet: $showAccountSheet)
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
        }
        .environment(themeManager)
        .sheet(isPresented: $showAccountSheet) {
            AccountSheet()
        }
    }
}

// MARK: - Top Bar

private struct TopBarView: View {
    @Binding var showAccountSheet: Bool
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 10) {
            LiveIndicatorView()

            Text("LIVE")
                .font(.gtStandard(size: 18))
                .fontWeight(.semibold)
                .foregroundStyle(themeManager.theme.foreground)

            Spacer()

            RightIconsView(showAccountSheet: $showAccountSheet)
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
    @Binding var showAccountSheet: Bool
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: "bell.fill")

            Button {
                showAccountSheet = true
            } label: {
                Image(systemName: "gearshape.fill")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    themeManager.cycleTheme()
                }
            } label: {
                Image(systemName: "paintpalette.fill")
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
            let scaleX = naturalTextWidth > 0 ? geo.size.width / naturalTextWidth : 1
            let scaleY = referenceCapHeight > 0 ? geo.size.height / referenceCapHeight : 1

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

            Group {
                if showTrackPicker {
                    InlineTrackPicker(
                        tracks: tracks,
                        selectedIndex: $selectedTrackIndex,
                        onConfirm: {
                            withAnimation(.spring(duration: 0.45)) {
                                showTrackPicker = false
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                } else {
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
                    .transition(.opacity)
                    .padding(.top, 28)
                    .padding(.bottom, 36)
                }
            }
            .animation(.spring(duration: 0.45), value: showTrackPicker)
        }
        .padding(.top, 10)
    }
}

// MARK: - Inline Track Picker (custom wheel)

private struct InlineTrackPicker: View {
    let tracks: [LofiTrack]
    @Binding var selectedIndex: Int
    let onConfirm: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    private let itemHeight: CGFloat = 52
    private let visibleCount = 3
    @State private var dragOffset: CGFloat = 0

    private func centredIndex(drag: CGFloat) -> Int {
        let raw = Double(selectedIndex) - Double(drag) / Double(itemHeight)
        return max(0, min(Int(round(raw)), tracks.count - 1))
    }

    var body: some View {
        let totalHeight = itemHeight * CGFloat(visibleCount)
        let baseOffset = totalHeight / 2 - itemHeight / 2 - CGFloat(selectedIndex) * itemHeight
        let rawCenter = Double(selectedIndex) - Double(dragOffset) / Double(itemHeight)

        VStack(spacing: 0) {
            ForEach(tracks.indices, id: \.self) { i in
                let dist = abs(Double(i) - rawCenter)
                let size = CGFloat(28) + CGFloat(max(0, 1 - dist)) * 6.77
                let opacity = max(0.15, 1.0 - dist * 0.55)

                Text(tracks[i].name)
                    .font(.system(size: size, weight: dist < 0.5 ? .semibold : .regular))
                    .foregroundStyle(themeManager.theme.foreground.opacity(opacity))
                    .frame(height: itemHeight)
                    .frame(maxWidth: .infinity)
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
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let newIndex = centredIndex(drag: value.predictedEndTranslation.height)
                    withAnimation(.spring(duration: 0.3)) {
                        selectedIndex = newIndex
                        dragOffset = 0
                    }
                }
        )
        .frame(height: totalHeight)
        .clipped()
    }
}

// MARK: - Mixer Slider

private struct MixerSliderView: View {
    @Binding var balance: Double
    @Environment(ThemeManager.self) private var themeManager
    @State private var dragStartBalance: Double?

    private let thumbWidth: CGFloat = 62
    private let trackHeight: CGFloat = 29
    private let thumbMinX: CGFloat = 38

    var body: some View {
        GeometryReader { geo in
            let thumbMaxX = geo.size.width - thumbWidth - 38
            let usableRange = thumbMaxX - thumbMinX
            let thumbX = thumbMinX + CGFloat(balance) * usableRange

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(themeManager.theme.foreground.opacity(0.2))

                Image(systemName: "headphones")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(themeManager.theme.foreground)
                    .frame(width: 20)
                    .offset(x: 14)

                Image(systemName: "airplane")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(themeManager.theme.foreground)
                    .frame(width: 20)
                    .offset(x: geo.size.width - 34)

                Capsule()
                    .fill(themeManager.theme.foreground)
                    .frame(width: thumbWidth)
                    .offset(x: thumbX)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let start = dragStartBalance ?? balance
                                if dragStartBalance == nil { dragStartBalance = balance }
                                let delta = Double(value.translation.width) / Double(usableRange)
                                balance = max(0, min(start + delta, 1))
                            }
                            .onEnded { _ in
                                dragStartBalance = nil
                            }
                    )
            }
        }
        .frame(height: trackHeight)
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
    ContentView()
}
