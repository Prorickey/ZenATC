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

            ZStack {
                AudioWavesView(amplitude: 1 - audio.balance, seed: audio.selectedTrackIndex)
                    .id(audio.selectedTrackIndex)
                    .transition(.opacity)
            }
            .frame(height: 136)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.5), value: audio.selectedTrackIndex)

            VStack(spacing: 0) {
                TopBarView(audio: audio, showSettings: $showSettings, showAirports: $showAirports, isPlaying: $audio.isPlaying)
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

            if showSettings {
                SettingsView(
                    authManager: authManager,
                    purchaseManager: purchaseManager,
                    showSettings: $showSettings,
                    showUpgrade: $showUpgrade,
                    currentAirportIndex: $audio.currentAirportIndex
                )
                .transition(.move(edge: .bottom))
                .zIndex(3)
            }

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
    let audio: AudioManager
    @Binding var showSettings: Bool
    @Binding var showAirports: Bool
    @Binding var isPlaying: Bool
    @Environment(ThemeManager.self) private var themeManager
    @State private var picking = false

    private let options = [5, 15, 30, 60, 90]
    private let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)
    private let popSpring = Animation.spring(response: 0.35, dampingFraction: 0.62)

    private var running: Bool { audio.sleepActive }
    private var showingTimer: Bool { picking || running }

    var body: some View {
        HStack(spacing: 10) {
            if picking {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        audio.startSleepTimer(minutes: minutes)
                        picking = false
                    } label: {
                        pill("\(minutes)m")
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
            } else {
                LiveIndicatorView(isPlaying: isPlaying, pausedColor: themeManager.theme.foreground)
                    .transition(.opacity)
                AnimatedStatusText(text: isPlaying ? "LIVE" : "Paused", color: themeManager.theme.foreground)
                    .transition(.opacity)
                Spacer(minLength: 0)
                if running {
                    pill(mmss(audio.sleepRemaining))
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .scale(scale: 0.1).combined(with: .opacity)
                        ))
                }
            }

            // Persistent moon/✕ — rests left of the icons (where the moon lives) in idle
            // & running, slides to the far-right while picking, and morphs glyph in place.
            moonToggle

            if !picking {
                RightIconsView(showSettings: $showSettings, showAirports: $showAirports)
                    .transition(.opacity)
            }
        }
        .frame(height: 30)
        .animation(spring, value: picking)
        .animation(popSpring, value: running)
        .sensoryFeedback(.impact(weight: .light), trigger: picking)
        .sensoryFeedback(.selection, trigger: audio.sleepActive)
    }

    private var moonToggle: some View {
        Button {
            if running {
                audio.cancelSleepTimer()
            } else {
                picking.toggle()
            }
        } label: {
            Image(systemName: showingTimer ? "xmark" : "moon.fill")
                .font(.system(size: 20))
                .scaleEffect(x: 0.88, y: 1.0)
                .foregroundStyle(themeManager.theme.foreground)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.gtStandardAirport(size: 16))
            .fontWeight(.heavy)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(themeManager.theme.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(themeManager.theme.foreground.opacity(0.2)))
    }

    private func mmss(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
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

            // Leading sweep line position (from top, rotating clockwise).
            let baseAngle = fraction * 2 * .pi - .pi / 2
            let coneSpread: Double = .pi / 2 

            // Line 1 leads (bright); line 2 sits `coneSpread` behind it. The fading
            // trail fills only the cone between them so it's enclosed by line 2,
            // rather than each line dragging its own long trail.
            let leadAngle = baseAngle
            let backAngle = baseAngle - coneSpread

            // Flat semi-transparent fill spanning the whole cone between the two
            // lines (no fade). Bump coneOpacity for a denser wedge.
            let coneOpacity: Double = 0.42
            var cone = Path()
            cone.move(to: center)
            cone.addArc(center: center, radius: radius,
                        startAngle: .radians(backAngle), endAngle: .radians(leadAngle), clockwise: false)
            cone.closeSubpath()
            context.fill(cone, with: .color(color.opacity(coneOpacity)))

            // Both sweep lines from center to ring edge.
            for angle in [leadAngle, backAngle] {
                var line = Path()
                line.move(to: center)
                line.addLine(to: CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                ))
                context.stroke(line, with: .color(color.opacity(0.90)), lineWidth: 1.5)
            }
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
                    .font(.gtStandardAirport(size: 20))
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

    @State private var movingForward = true

    private static let flickSpring: Animation = .spring(response: 0.4, dampingFraction: 0.85)
    private let flickThreshold: CGFloat = 40
    private let flickPredictedThreshold: CGFloat = 180

    var body: some View {
        AirportPageView(airport: airports[currentIndex], dragY: dragY)
            .id(currentIndex)
            .transition(.asymmetric(
                insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard !showTrackPicker else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        let predicted = value.predictedEndTranslation

                        if abs(dx) > abs(dy) {
                            if (dx < -flickThreshold || predicted.width < -flickPredictedThreshold),
                               currentIndex < airports.count - 1 {
                                movingForward = true
                                withAnimation(Self.flickSpring) {
                                    currentIndex += 1
                                }
                            } else if (dx > flickThreshold || predicted.width > flickPredictedThreshold),
                                      currentIndex > 0 {
                                movingForward = false
                                withAnimation(Self.flickSpring) {
                                    currentIndex -= 1
                                }
                            }
                        } else {
                            if dy < -40 || predicted.height < -80 {
                                onOpen()
                            }
                        }
                    }
            )
    }
}

private struct AirportPageView: View {
    let airport: Airport
    let dragY: CGFloat
    @Environment(ThemeManager.self) private var themeManager
    @State private var naturalTextWidth: CGFloat = 0
    @State private var naturalTextHeight: CGFloat = 0

    // ── Tune default letter size here ──────────────────────────────────────
    private let defaultWidthFraction: CGFloat  = 1   // fraction of container width
    private let defaultHeightFraction: CGFloat = 0.80
    // fraction of container height
    // ───────────────────────────────────────────────────────────────────────

    private let referenceCapHeight: CGFloat = UIFont.abcGravity(size: 600).capHeight

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
            let posY = geo.size.height / 2 + referenceCapHeight * (finalScaleY - baseScaleY) / 2 + geo.size.height * 0.10

            Text(airport.code.uppercased())
                .font(.airportCode(size: 600))
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
            .offset(y: showTrackPicker ? -80 : 5)
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
                        .font(.gtStandardAirport(size: 34.77))
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

    var body: some View {
        let totalHeight = itemHeight * CGFloat(visibleCount)
        let middleSlot = (visibleCount - 1) / 2
        let baseOffset = CGFloat(middleSlot - selectedIndex) * itemHeight
        let rawCenter = Double(selectedIndex) - Double(dragOffset) / Double(itemHeight)

        GeometryReader { geo in
            let availableWidth = geo.size.width - 32

            VStack(spacing: 0) {
                ForEach(tracks.indices, id: \.self) { pos in
                    let dist = abs(Double(pos) - rawCenter)
                    let size = CGFloat(28) + CGFloat(max(0, 1 - dist)) * 6.77
                    let opacity = max(0.15, 1.0 - dist * 0.55)
                    let fits = (textWidths[pos] ?? 0) <= availableWidth
                    let isSelected = pos == selectedIndex

                    Text(tracks[pos].name)
                        .font(.gtStandardAirport(size: isSelected ? 34.77 : size))
                        .fontWeight(.heavy)
                        .foregroundStyle(themeManager.theme.foreground.opacity(opacity))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: TextWidthKey.self, value: [pos: proxy.size.width])
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
                        let tappedPos = Int((value.startLocation.y - baseOffset) / itemHeight)
                        let clampedPos = max(0, min(tappedPos, tracks.count - 1))
                        dragOffset = 0
                        if clampedPos == selectedIndex {
                            onConfirm()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedIndex = clampedPos
                            }
                        }
                        return
                    }
                    let raw = Double(selectedIndex) - Double(value.predictedEndTranslation.height) / Double(itemHeight)
                    let newPos = max(0, min(Int(round(raw)), tracks.count - 1))
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedIndex = newPos
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
    // True between a tap-jump and the gesture committing to a real drag. While set,
    // small finger jitter is ignored so the tap's spring can finish (slide) instead
    // of being snapped by the un-animated drag branch (instant jump).
    @State private var didTapJump = false

    var body: some View {
        GeometryReader { geo in
            let scale: CGFloat = 1.5
            let trackHeight: CGFloat = 29 * scale
            let thumbWidth: CGFloat = (isDragging ? 66 : 62 * 0.7) * scale
            let thumbHeight: CGFloat = trackHeight
            let trackInset: CGFloat = 2 * scale
            let iconInset: CGFloat = 14 * scale
            let iconFrame: CGFloat = 20 * scale

            let usableRange = max(geo.size.width - (trackInset * 2) - thumbWidth, 1)
            let baseThumbLeft = trackInset + CGFloat(balance) * usableRange
            let baseThumbRight = baseThumbLeft + thumbWidth
            // End-state pill stays centered on the icon but is wide enough that its
            // outer edge reaches the very end of the background capsule (x = 0 / width),
            // rather than stopping a few points short.
            let endClipWidth = iconFrame + 2 * iconInset
            let endZone: CGFloat = 10 * scale
            let leftDistance = max(baseThumbLeft - trackInset, 0)
            let rightDistance = max((geo.size.width - trackInset) - baseThumbRight, 0)
            let leftProgress = max(0, min((endZone - leftDistance) / endZone, 1))
            let rightProgress = max(0, min((endZone - rightDistance) / endZone, 1))
            let endProgress = max(leftProgress, rightProgress)
            let smoothProgress = endProgress * endProgress * (3 - 2 * endProgress)
            // While pressed at an end the pill would otherwise stay collapsed to the
            // icon-sized clip. Let the press expand it back toward full thumb width, but
            // anchored to the end it's resting on so it only grows inward (left end →
            // grows right, right end → grows left). Zero when not pressed (thumbWidth
            // shrinks below the clip) or away from the ends (smoothProgress 0).
            // edgeExpandFactor tunes how far it grows inward: 1 = full thumb width, 0 = none.
            let edgeExpandFactor: CGFloat = 0.4
            let edgeExpand = max(0, thumbWidth - endClipWidth) * smoothProgress * edgeExpandFactor
            let clipWidth = thumbWidth - (thumbWidth - endClipWidth) * smoothProgress + edgeExpand
            // At the ends the clipped pill grows past the nominal thumb width, so the
            // capsule hosting it must grow too — otherwise the visible pill is capped
            // short of the track end. Equals thumbWidth everywhere except the end morph.
            let capsuleWidth = max(thumbWidth, clipWidth)
            let leftIconCenter = iconInset + (iconFrame / 2)
            let rightIconCenter = geo.size.width - iconInset - (iconFrame / 2)
            let atRightEnd = rightProgress > leftProgress
            let targetCenter = atRightEnd ? rightIconCenter : leftIconCenter
            let baseCenter = baseThumbLeft + (thumbWidth / 2)
            // Shift the center by half the inward growth so the outer (pinned) edge holds.
            let edgeShift = (atRightEnd ? -edgeExpand : edgeExpand) / 2
            let desiredCenter = baseCenter + (targetCenter - baseCenter) * smoothProgress + edgeShift
            let thumbX = desiredCenter - (capsuleWidth / 2)

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
                    .frame(width: capsuleWidth, height: thumbHeight)
                    .mask(alignment: .center) {
                        RoundedRectangle(cornerRadius: thumbHeight / 2)
                            .frame(width: clipWidth, height: thumbHeight)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
                            .animation(.easeOut(duration: 0.70), value: smoothProgress)
                    }
                    .offset(x: thumbX)

                // Knockout icons (theme background) masked to the pill shape — visible only where pill covers them
                ZStack(alignment: .leading) {
                    Color.clear

                    Image(systemName: "headphones")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(themeManager.theme.background)
                        .frame(width: iconFrame)
                        .offset(x: iconInset)

                    Image(systemName: "airplane")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(themeManager.theme.background)
                        .frame(width: iconFrame)
                        .offset(x: geo.size.width - iconInset - iconFrame)
                }
                .mask(alignment: .leading) {
                    Capsule()
                        .frame(width: capsuleWidth, height: thumbHeight)
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
                                didTapJump = true
                                return
                            }
                            dragStartBalance = balance
                        }
                        // Only the un-animated branch can produce an instant jump. After a
                        // tap-jump require a much larger movement before engaging it, so a
                        // tap's slight finger jitter lets the spring slide instead of snapping.
                        let dragThreshold: CGFloat = didTapJump ? 20 : 8
                        if abs(value.translation.width) > dragThreshold {
                            let start = dragStartBalance ?? balance
                            let delta = Double(value.translation.width / usableRange)
                            balance = min(max(start + delta, 0), 1)
                            didTapJump = false
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        isSliderActive = false
                        dragStartBalance = nil
                        didTapJump = false
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        }
        .frame(height: 36 * 1.5)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: Int(balance * 10))
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: isDragging) { _, newValue in
            newValue
        }
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

// MARK: - Audio Waves

private struct AudioWavesView: View {
    let amplitude: Double   // 0..1, scales bar height
    let seed: Int           // varies per song; produces a unique irregular pattern
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let color = themeManager.theme.foreground
        let s = seed
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let t: Double = context.date.timeIntervalSinceReferenceDate
                let barCount = 40
                let barSpacing: CGFloat = size.width / CGFloat(barCount)
                let maxBarHeight: CGFloat = size.height
                let amp: Double = amplitude

                // Per-song wave-shape parameters (constant across bars).
                let phaseSeed: Double = AudioWavesView.rand(s) * .pi * 2
                let wavelengths: Double = 1.8 + AudioWavesView.rand(s &* 7 &+ 1) * 0.8   // 1.8..2.6 full cycles across the bars
                let wavelengths2: Double = 0.7 + AudioWavesView.rand(s &* 11 &+ 2) * 0.4  // slow counter-ripple

                // Shared lofi beat groove (~78 BPM, 4/4): kick on beats 1 & 3, snare
                // backbeat on 2 & 4. Gaussian pulses give a percussive "punch" that
                // swells the whole wave in time, rather than a smooth sine throb.
                let beatsPerSec: Double = 78 / 60.0
                let beatInBar: Double = (t * beatsPerSec).truncatingRemainder(dividingBy: 4.0) // 0..4
                func pulse(_ pos: Double, _ width: Double) -> Double {
                    let d: Double = abs(beatInBar - pos)
                    let wrapped: Double = min(d, 4.0 - d)            // wrap so beat 4 → 0 is seamless
                    return exp(-(wrapped * wrapped) / (width * width))
                }
                let kick: Double = pulse(0, 0.16) + pulse(2, 0.16)
                let snare: Double = (pulse(1, 0.13) + pulse(3, 0.13)) * 0.6
                let beat: Double = min(1.0, kick + snare)

                for i in 0..<barCount {
                    let x: CGFloat = CGFloat(i) * barSpacing + barSpacing / 2
                    let frac: Double = Double(i) / Double(max(1, barCount - 1))   // 0=left, 1=right

                    // Genuine traveling wave: a primary sine sweeping across the bars,
                    // plus a slower counter-ripple for organic motion.
                    let theta1: Double = frac * .pi * 2 * wavelengths - t * 1.3 + phaseSeed
                    let theta2: Double = frac * .pi * 2 * wavelengths2 + t * 0.6 + phaseSeed
                    let wave: Double = sin(theta1) * 0.78 + sin(theta2) * 0.22   // ~ -1..1
                    let waveNorm: Double = (wave + 1.0) / 2.0

                    // Per-bar shimmer — gentle jitter so bars stay alive between beats.
                    let rj: Double = AudioWavesView.rand(i &* 47 &+ s &* 5 &+ 1)
                    let shimmer: Double = (sin(t * (3.0 + rj * 1.5) + rj * .pi * 2) + 1) / 2

                    // Wave-dominant baseline, lifted by the beat: a uniform punch across
                    // all bars plus extra lift where the wave is already cresting.
                    let baseline: Double = 0.16 + 0.40 * waveNorm + 0.06 * shimmer
                    let beatSwell: Double = 0.30 * beat + 0.16 * beat * waveNorm
                    let normalized: Double = max(0.0, min(1.0, baseline + beatSwell))

                    let height: CGFloat = maxBarHeight * CGFloat(normalized * amp)
                    guard height > 0.5 else { continue }
                    let barWidth: CGFloat = barSpacing * 0.5
                    let rect = CGRect(
                        x: x - barWidth / 2,
                        y: size.height - height,
                        width: barWidth,
                        height: height
                    )
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(color))
                }
            }
        }
    }

    /// Stable pseudo-random in 0..1 from an Int key (xor-shift on a Knuth-multiplied seed).
    private static func rand(_ n: Int) -> Double {
        var x = UInt32(truncatingIfNeeded: n &* 2654435761)
        x ^= x &<< 13
        x ^= x &>> 17
        x ^= x &<< 5
        return Double(x) / Double(UInt32.max)
    }
}

#Preview {
    ContentView(authManager: AuthManager(), purchaseManager: PurchaseManager())
}
