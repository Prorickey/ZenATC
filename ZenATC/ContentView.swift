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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var isSliderActive = false
    @State private var volumeMonitor = VolumeMonitor()
    @State private var volumeOverlaySnoozed = false

    private let airports = Airport.all
    private let tracks = LofiTrack.all

    var body: some View {
        @Bindable var audio = audio
        let showVolumeOverlay = volumeMonitor.volume <= 0 && !volumeOverlaySnoozed

        ZStack(alignment: .top) {
            themeManager.theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TopBarView(showSettings: $showSettings, showAirports: $showAirports, isPlaying: $audio.isPlaying)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                Spacer().frame(height: 10)

                AirportCarouselView(
                    airports: airports,
                    currentIndex: $audio.currentAirportIndex,
                    dragY: showTrackPicker ? -200 : 0,
                    showTrackPicker: showTrackPicker,
                    onOpen: {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                            showTrackPicker = true
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .onChange(of: audio.currentAirportIndex) { audio.reloadATC() }

                BottomControlsView(
                    balance: $audio.balance,
                    isPlaying: $audio.isPlaying,
                    tracks: tracks,
                    selectedTrackIndex: $audio.selectedTrackIndex,
                    showTrackPicker: $showTrackPicker,
                    isSliderActive: $isSliderActive
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

            if showVolumeOverlay {
                VolumeTooLowView(onContinue: {
                    volumeOverlaySnoozed = true
                })
                .transition(.opacity)
                .zIndex(20)
            }
        }

        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard !isSliderActive else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dy) > abs(dx) else { return }
                    let predicted = value.predictedEndTranslation.height
                    if showTrackPicker, dy > 60 {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                            showTrackPicker = false
                        }
                    } else if !showTrackPicker, dy < -40 || predicted < -80 {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                            showTrackPicker = true
                        }
                    }
                }
        )
        .onChange(of: volumeMonitor.volume) { _, newVolume in
            if newVolume > 0 {
                volumeOverlaySnoozed = false
            }
        }
        .animation(.easeInOut(duration: 0.6), value: showVolumeOverlay)
        .onAppear { hasCompletedOnboarding = true }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showSettings)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showUpgrade)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showAirports)
        .animation(.easeInOut(duration: 0.6), value: hasCompletedOnboarding)
        .sensoryFeedback(.impact(weight: .light), trigger: showTrackPicker)
        .sensoryFeedback(.impact(weight: .medium), trigger: audio.currentAirportIndex)
        .environment(themeManager)
    }
}

// MARK: - Top Bar

private struct TopBarView: View {
    @Binding var showSettings: Bool
    @Binding var showAirports: Bool
    @Binding var isPlaying: Bool
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 10) {
            LiveIndicatorView(isPlaying: isPlaying, pausedColor: themeManager.theme.foreground)

            AnimatedStatusText(
                text: isPlaying ? "LIVE" : "Paused",
                color: themeManager.theme.foreground
            )

            Spacer()

            RightIconsView(showSettings: $showSettings, showAirports: $showAirports)
        }
    }
}

// MARK: - Live Indicator

private struct LiveIndicatorView: View {
    let isPlaying: Bool
    let pausedColor: Color
    @Environment(ThemeManager.self) private var themeManager
    private let liveDotSize: CGFloat = 10
    private let radarDiameter: CGFloat = 22
    private let pauseBarWidth: CGFloat = 4
    private let pauseBarHeight: CGFloat = 14
    private let pauseBarSpacing: CGFloat = 4
    private let sweepPeriod: Double = 3.5

    var body: some View {
        ZStack {
            if isPlaying {
                TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
                    let t = timeline.date.timeIntervalSince1970
                    let fraction = (t / sweepPeriod).truncatingRemainder(dividingBy: 1.0)
                    RadarSweepView(fraction: fraction, color: themeManager.theme.foreground)
                        .frame(width: radarDiameter, height: radarDiameter)
                }
            }

            Circle()
                .fill(themeManager.theme.foreground)
                .frame(width: liveDotSize, height: liveDotSize)
                .opacity(isPlaying ? 1 : 0)
                .scaleEffect(isPlaying ? 1 : 0.2)

            PauseGlyph(
                color: pausedColor,
                barWidth: pauseBarWidth,
                barHeight: pauseBarHeight,
                barSpacing: pauseBarSpacing
            )
            .opacity(isPlaying ? 0 : 1)
            .scaleEffect(isPlaying ? 0.88 : 1)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPlaying)
    }
}

private struct RadarSweepView: View {
    let fraction: Double
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2 - 1

            // Filled dim disc — low-opacity radar screen background
            var disc = Path()
            disc.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
            context.fill(disc, with: .color(color.opacity(0.10)))

            // Static halo ring
            context.stroke(disc, with: .color(color.opacity(0.30)), lineWidth: 1.5)

            // Sweep line angle: start from top (−π/2), rotate clockwise
            let currentAngle = fraction * 2 * .pi - .pi / 2
            let trailArc: Double = .pi / 2  // 90° fading trail

            // Trail: filled pie-wedge slices spanning center→edge, fading from
            // transparent at the tail to solid just behind the sweep line
            let segments = 24
            for i in 0..<segments {
                let t0 = Double(i) / Double(segments)
                let t1 = Double(i + 1) / Double(segments)
                let a0 = currentAngle - trailArc + t0 * trailArc
                let a1 = currentAngle - trailArc + t1 * trailArc
                var wedge = Path()
                wedge.move(to: center)
                wedge.addArc(center: center, radius: radius,
                             startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                wedge.closeSubpath()
                context.fill(wedge, with: .color(color.opacity(t0 * 0.55)))
            }

            // Sweep line from center to ring edge
            var line = Path()
            line.move(to: center)
            line.addLine(to: CGPoint(
                x: center.x + cos(currentAngle) * radius,
                y: center.y + sin(currentAngle) * radius
            ))
            context.stroke(line, with: .color(color.opacity(0.90)), lineWidth: 1.5)
        }
    }
}

private struct PauseGlyph: View {
    let color: Color
    let barWidth: CGFloat
    let barHeight: CGFloat
    let barSpacing: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: barWidth, height: barHeight)
                .offset(x: -(barSpacing / 2 + barWidth / 2))

            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: barWidth, height: barHeight)
                .offset(x: (barSpacing / 2 + barWidth / 2))
        }
    }
}

private struct AnimatedStatusText: View {
    let text: String
    let color: Color

    var body: some View {
        let letters = Array(text)

        HStack(spacing: 0) {
            ForEach(letters.indices, id: \.self) { index in
                Text(String(letters[index]))
                    .font(.airportCode(size: 20))
                    .fontWeight(.heavy)
                    .foregroundStyle(color)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(
                        .easeOut(duration: 0.25).delay(Double(index) * 0.03),
                        value: text
                    )
            }
        }
    }
}

// MARK: - Right Icons

private struct RightIconsView: View {
    @Binding var showSettings: Bool
    @Binding var showAirports: Bool
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 14) {
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
                Image(systemName: "slider.horizontal.3")
            }
        }
        .font(.system(size: 20))
        .scaleEffect(x: 0.88, y: 1.0)
        .foregroundStyle(themeManager.theme.foreground)
        .buttonStyle(.plain)
    }
}

// MARK: - Airport Carousel

private struct AirportCarouselView: View {
    let airports: [Airport]
    @Binding var currentIndex: Int
    let dragY: CGFloat
    let showTrackPicker: Bool
    let onOpen: () -> Void

    @State private var dragTranslation: CGFloat = 0

    private static let flickSpring: Animation = .spring(response: 0.3, dampingFraction: 0.7)
    private static let returnSpring: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    private let flickThreshold: CGFloat = 40
    private let flickPredictedThreshold: CGFloat = 180

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(airports.indices, id: \.self) { i in
                    AirportPageView(airport: airports[i], dragY: dragY)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .offset(x: -CGFloat(currentIndex) * geo.size.width + dragTranslation)
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !showTrackPicker else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dy) > abs(dx) { return }
                        dragTranslation = dx
                    }
                    .onEnded { value in
                        guard !showTrackPicker else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height

                        if abs(dy) > abs(dx) {
                            let predicted = value.predictedEndTranslation.height
                            if dy < -40 || predicted < -80 {
                                onOpen()
                            }
                            withAnimation(Self.returnSpring) {
                                dragTranslation = 0
                            }
                            return
                        }

                        let predictedDx = value.predictedEndTranslation.width

                        if (dx < -flickThreshold || predictedDx < -flickPredictedThreshold) && currentIndex < airports.count - 1 {
                            withAnimation(Self.flickSpring) {
                                currentIndex += 1
                                dragTranslation = 0
                            }
                        } else if (dx > flickThreshold || predictedDx > flickPredictedThreshold) && currentIndex > 0 {
                            withAnimation(Self.flickSpring) {
                                currentIndex -= 1
                                dragTranslation = 0
                            }
                        } else {
                            withAnimation(Self.returnSpring) {
                                dragTranslation = 0
                            }
                        }
                    }
            )
        }
    }
}

private struct AirportPageView: View {
    let airport: Airport
    let dragY: CGFloat
    @Environment(ThemeManager.self) private var themeManager
    @State private var naturalTextWidth: CGFloat = 0
    @State private var naturalTextHeight: CGFloat = 0

    // ── Tune default letter size here ──────────────────────────────────────
    private let defaultWidthFraction: CGFloat  = 0.98   // fraction of container width
    private let defaultHeightFraction: CGFloat = 0.96
    // fraction of container height
    // ───────────────────────────────────────────────────────────────────────

    private let referenceCapHeight: CGFloat = UIFont.abcGravity(size: 200).capHeight

    var body: some View {
        GeometryReader { geo in
            let baseScaleX = naturalTextWidth > 0
                ? (geo.size.width / naturalTextWidth) * defaultWidthFraction
                : 1
            let baseScaleY = referenceCapHeight > 0
                ? (geo.size.height / referenceCapHeight) * defaultHeightFraction
                : 1
            let clampedDragY = min(max(dragY, -200), 0)
            let stretchDelta = naturalTextHeight > 0 ? clampedDragY / naturalTextHeight : 0
            let finalScaleY = max(baseScaleY * 0.800, baseScaleY + stretchDelta)
            // posY uses referenceCapHeight (visible glyph) so the cap's top stays pinned.
            let posY = geo.size.height / 2 + referenceCapHeight * (finalScaleY - baseScaleY) / 2

            Text(airport.code.uppercased())
                .font(.airportCode(size: 200))
                .kerning(0)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(themeManager.theme.foreground)
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear {
                            if naturalTextWidth == 0 {
                                naturalTextWidth = proxy.size.width
                                naturalTextHeight = proxy.size.height
                            }
                        }
                    }
                )
                .scaleEffect(x: baseScaleX, y: finalScaleY, anchor: .center)
                .position(x: geo.size.width / 2, y: posY)
                .opacity(naturalTextWidth == 0 ? 0 : 1)
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: dragY)
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
    @Binding var isSliderActive: Bool
    @Environment(ThemeManager.self) private var themeManager

    private static let pickerSpring: Animation = .spring(response: 0.55, dampingFraction: 0.85)
    private static let fadeDuration: Double = 0.25
    private static let fadeStagger: Double = 0.2

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                MixerSliderView(balance: $balance, isSliderActive: $isSliderActive)
                    .padding(.horizontal, 20)

                PlayPauseButton(isPlaying: $isPlaying)
                    .padding(.top, 16)
            }
            .offset(y: showTrackPicker ? -80 : 25)
            .animation(Self.pickerSpring, value: showTrackPicker)

            ZStack {
                InlineTrackPicker(
                    tracks: tracks,
                    selectedIndex: $selectedTrackIndex,
                    isExpanded: showTrackPicker,
                    onConfirm: {
                        withAnimation(Self.pickerSpring) {
                            showTrackPicker = false
                        }
                    }
                )
                .offset(y: -70)
                .opacity(showTrackPicker ? 1 : 0)
                .animation(
                    .easeInOut(duration: Self.fadeDuration).delay(showTrackPicker ? Self.fadeStagger : 0),
                    value: showTrackPicker
                )
                .allowsHitTesting(showTrackPicker)

                Button {
                    withAnimation(Self.pickerSpring) {
                        showTrackPicker = true
                    }
                } label: {
                    Text(tracks[selectedTrackIndex].name)
                        .font(.airportCode(size: 34.77))
                        .fontWeight(.heavy)
                        .kerning(0)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(themeManager.theme.foreground)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(showTrackPicker ? 0 : 1)
                .animation(
                    .easeInOut(duration: Self.fadeDuration).delay(showTrackPicker ? 0 : Self.fadeStagger),
                    value: showTrackPicker
                )
                .offset(y: -18)
                .allowsHitTesting(!showTrackPicker)
            }
            .padding(.top, 16)
            .padding(.bottom, 50)
        }
        .padding(.top, 20)
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
    @State private var displayOrder: [Int] = []

    private func rebuildDisplayOrder() {
        guard !tracks.isEmpty else { displayOrder = []; return }
        let n = tracks.count
        let start = max(0, min(selectedIndex, n - 1))
        displayOrder = (0..<n).map { (start + $0) % n }
    }

    var body: some View {
        let totalHeight = itemHeight * CGFloat(visibleCount)
        let selectedDisplayPos = displayOrder.firstIndex(of: selectedIndex) ?? 0
        let baseOffset = -CGFloat(selectedDisplayPos) * itemHeight
        let rawCenter = Double(selectedDisplayPos) - Double(dragOffset) / Double(itemHeight)

        GeometryReader { geo in
            let availableWidth = geo.size.width - 32

            VStack(spacing: 0) {
                ForEach(displayOrder.indices, id: \.self) { pos in
                    let origIndex = displayOrder[pos]
                    let dist = abs(Double(pos) - rawCenter)
                    let size = CGFloat(28) + CGFloat(max(0, 1 - dist)) * 6.77
                    let opacity = max(0.15, 1.0 - dist * 0.55)
                    let fits = (textWidths[origIndex] ?? 0) <= availableWidth
                    let isSelected = origIndex == selectedIndex

                    Text(tracks[origIndex].name)
                        .font(.airportCode(size: isSelected ? 34.77 : size))
                        .fontWeight(.heavy)
                        .foregroundStyle(themeManager.theme.foreground.opacity(opacity))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: TextWidthKey.self, value: [origIndex: proxy.size.width])
                            }
                        )
                        .frame(height: fits ? itemHeight : 0)
                        .frame(maxWidth: .infinity)
                        .opacity(fits ? 1 : 0)
                        .contentShape(Rectangle())
                }
            }
            .offset(y: baseOffset + dragOffset)
            .onPreferenceChange(TextWidthKey.self) { value in
                textWidths.merge(value) { _, new in new }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let distance = abs(value.translation.height)
                    if distance < 5 {
                        let tappedPos = Int(value.startLocation.y / itemHeight)
                        let clampedPos = max(0, min(tappedPos, displayOrder.count - 1))
                        let tappedIndex = displayOrder[clampedPos]
                        dragOffset = 0
                        if tappedIndex == selectedIndex {
                            onConfirm()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedIndex = tappedIndex
                            }
                        }
                        return
                    }
                    let raw = Double(selectedDisplayPos) - Double(value.predictedEndTranslation.height) / Double(itemHeight)
                    let newPos = max(0, min(Int(round(raw)), displayOrder.count - 1))
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedIndex = displayOrder[newPos]
                        dragOffset = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onConfirm()
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: selectedIndex)
        .frame(height: totalHeight)
        .clipped()
        .onAppear { rebuildDisplayOrder() }
        .onChange(of: isExpanded) { _, expanded in
            if expanded { rebuildDisplayOrder() }
        }
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
    @Binding var isSliderActive: Bool
    @Environment(ThemeManager.self) private var themeManager
    @State private var isDragging = false
    @State private var dragStartBalance: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let scale: CGFloat = 1.5
            let trackHeight: CGFloat = 29 * scale
            let thumbWidth: CGFloat = (isDragging ? 66 : 62 * 0.7) * scale
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
                            .animation(.easeOut(duration: 0.70), value: smoothProgress)
                    }
                    .offset(x: thumbX)

                // White icons masked to the pill shape — visible only where pill covers them
                ZStack(alignment: .leading) {
                    Color.clear

                    Image(systemName: "headphones")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: iconFrame)
                        .offset(x: iconInset)

                    Image(systemName: "airplane")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
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
                        isSliderActive = true
                        if dragStartBalance == nil {
                            let thumbLeft = trackInset + CGFloat(balance) * usableRange
                            let thumbRight = thumbLeft + thumbWidth
                            if value.startLocation.x < thumbLeft || value.startLocation.x > thumbRight {
                                let targetLeft = value.startLocation.x - (thumbWidth / 2)
                                let newBalance = min(max(Double((targetLeft - trackInset) / usableRange), 0), 1)
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                    balance = newBalance
                                }
                                dragStartBalance = newBalance
                                return
                            }
                            dragStartBalance = balance
                        }
                        if abs(value.translation.width) > 5 {
                            let start = dragStartBalance ?? balance
                            let delta = Double(value.translation.width / usableRange)
                            balance = min(max(start + delta, 0), 1)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        isSliderActive = false
                        dragStartBalance = nil
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        }
        .frame(height: 36 * 1.5)
        .sensoryFeedback(.selection, trigger: Int(balance * 20))
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
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(isPlaying ? themeManager.theme.foreground : themeManager.theme.background)
                    .offset(x: isPlaying ? 0 : -1)
            }
        }
    }
}

#Preview {
    ContentView(authManager: AuthManager(), purchaseManager: PurchaseManager())
}
