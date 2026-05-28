//
//  AudioManager.swift
//  ZenATC
//

import AVFoundation
import MediaPlayer
import Observation

let backendBaseURL = URL(string: "https://zenatc.bedson.tech")!

// A single source previewed in isolation from the Settings screen.
enum AudioPreview: Equatable {
    case lofi(UUID)    // a specific lofi track
    case atc(String)   // an ATC filter (regular audio for now), keyed by filter name
}

@Observable
final class AudioManager {
    var isPlaying = false {
        didSet {
            guard !suppressObservers else { return }
            isPlaying ? startPlayback() : pausePlayback()
        }
    }

    // balance: 0 = full lofi (headphones), 1 = full ATC (airplane)
    var balance: Double = 0.5 {
        didSet {
            guard !suppressObservers else { return }
            updateVolumes()
        }
    }

    // Set while fade helpers mutate isPlaying/balance, so their didSet observers
    // don't fight the manual volume fades.
    private var suppressObservers = false

    var currentAirportIndex = 0

    let allTracks = LofiTrack.all
    // Which lofi tracks appear in the picker wheel. All enabled on launch;
    // toggling a pack off in Settings removes it from here (and the wheel).
    var enabledTrackIDs: Set<UUID> = Set(LofiTrack.all.map(\.id))
    // Selection is tracked by identity so it survives the available list changing.
    var selectedTrackID: UUID = LofiTrack.all[0].id

    var availableTracks: [LofiTrack] {
        allTracks.filter { enabledTrackIDs.contains($0.id) }
    }

    var selectedTrack: LofiTrack {
        allTracks.first { $0.id == selectedTrackID } ?? allTracks[0]
    }

    // Sleep timer — auto fade-out + pause after a chosen duration
    private(set) var sleepActive = false
    private(set) var sleepRemaining: TimeInterval = 0
    private var sleepEndDate: Date?
    private var sleepTicker: Timer?
    private var fadeTicker: Timer?
    private var fadeMultiplier: Float = 1.0

    // ATC: local bundle file, loops natively via AVAudioPlayer
    private var atcPlayer: AVAudioPlayer?
    // Lofi: VOD HLS stream — starts instantly, downloads ahead, loops from cache
    private var lofiPlayer: AVPlayer?
    private var lofiItem: AVPlayerItem?
    private var lofiLoopObserver: Any?
    private var lofiFadeTimer: Timer?
    private var cookieRefreshTask: Task<Void, Never>?

    // Settings preview — plays one source (a single lofi track OR ATC) on its own,
    // separate from the main mix. Exclusive: starting one stops any other.
    private(set) var activePreview: AudioPreview?
    private var previewLofiPlayer: AVPlayer?
    private var previewATCPlayer: AVAudioPlayer?

    private let airports = Airport.all
    private let attestationManager = AttestationManager(backendBaseURL: backendBaseURL)

    // ~30 segments × ~150KB each ≈ 4.5MB — enough for 2 min of 4s HLS segments
    private static let segmentCacheCapacity = 5 * 1024 * 1024
    private static let forwardBufferSeconds: TimeInterval = 120
    // The access cookie lives 5 min; refresh comfortably inside that window so
    // segment fetches never hit an expired cookie mid-playback.
    private static let cookieRefreshInterval: UInt64 = 240 * 1_000_000_000

    init() {
        configureCacheLimit()
        configureSession()
        configureRemoteCommands()
    }

    // Warms up the lofi stream (resolves the signed URL + access cookie via App
    // Attest and builds the player) so the first play is instant. Does not start
    // playback or the cookie-refresh loop — those begin when the user hits play.
    @MainActor
    func preload() async {
        loadATC()

        let streamURL = await resolveLofiURL(filename: selectedTrack.filename)
        tearDownLofi()

        lofiItem = AVPlayerItem(url: streamURL)
        lofiItem?.preferredForwardBufferDuration = Self.forwardBufferSeconds
        lofiPlayer = AVPlayer(playerItem: lofiItem)
        lofiPlayer?.volume = 0
        lofiPlayer?.automaticallyWaitsToMinimizeStalling = true
        installLoopObserver()
    }

    // MARK: - Private

    private func configureCacheLimit() {
        URLCache.shared = URLCache(
            memoryCapacity: Self.segmentCacheCapacity,
            diskCapacity: Self.segmentCacheCapacity
        )
    }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func startPlayback() {
        if atcPlayer == nil { loadATC() }
        updateVolumes()
        atcPlayer?.play()
        if lofiPlayer == nil {
            Task { await loadAndPlayLofi() }
        } else {
            lofiPlayer?.play()
            startCookieRefresh(immediate: true)
        }
        updateNowPlaying()
    }

    private func pausePlayback() {
        atcPlayer?.pause()
        lofiPlayer?.pause()
        stopCookieRefresh()
        updateNowPlaying()
    }

    func reloadATC() {
        atcPlayer?.stop()
        atcPlayer = nil
        loadATC()
        if isPlaying {
            updateVolumes()
            atcPlayer?.play()
        }
        updateNowPlaying()
    }

    func reloadLofi() {
        tearDownLofi()
        Task { await loadAndPlayLofi() }
        updateNowPlaying()
    }

    private func loadATC() {
        let filename = airports[currentAirportIndex].atcFilename
        guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3", subdirectory: "Audio")
                     ?? Bundle.main.url(forResource: filename, withExtension: "mp3")
        else { return }
        atcPlayer = try? AVAudioPlayer(contentsOf: url)
        atcPlayer?.numberOfLoops = -1
        atcPlayer?.prepareToPlay()
    }

    // Resolves the signed CDN URL via App Attest (which also sets the access
    // cookie), builds the player, and starts playback + the cookie-refresh loop.
    //
    // Play-through behaviour:
    //   Pass 1 — AVPlayer streams each 4-second segment from Cloudflare, buffering ahead.
    //   Pass 2+ — segments are in the local URL cache; playback is fully offline.
    @MainActor
    private func loadAndPlayLofi() async {
        let streamURL = await resolveLofiURL(filename: selectedTrack.filename)

        // Tear down any previous state before creating new objects.
        tearDownLofi()

        lofiItem = AVPlayerItem(url: streamURL)
        lofiItem?.preferredForwardBufferDuration = Self.forwardBufferSeconds
        lofiPlayer = AVPlayer(playerItem: lofiItem)
        installLoopObserver()

        updateVolumes()
        if isPlaying { lofiPlayer?.play() }
        startCookieRefresh(immediate: false)
    }

    // VOD HLS doesn't loop natively — seek back to the start and replay on end.
    private func installLoopObserver() {
        lofiLoopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: lofiItem,
            queue: .main
        ) { [weak self] _ in
            self?.lofiPlayer?.seek(to: .zero)
            if self?.isPlaying == true { self?.lofiPlayer?.play() }
        }
    }

    private func tearDownLofi() {
        stopCookieRefresh()
        if let obs = lofiLoopObserver {
            NotificationCenter.default.removeObserver(obs)
            lofiLoopObserver = nil
        }
        lofiPlayer?.pause()
        lofiPlayer = nil
        lofiItem = nil
        URLCache.shared.removeAllCachedResponses()
    }

    private func resolveLofiURL(filename: String) async -> URL {
        do {
            return try await attestationManager.requestStreamURL(for: filename)
        } catch {
            print("[AudioManager] attestation failed, using direct URL: \(error)")
            return backendBaseURL.appendingPathComponent("hls/\(filename)/index.m3u8")
        }
    }

    // MARK: - Access cookie refresh

    // Keeps the short-lived /hls/ access cookie fresh while lofi is playing, so
    // segment fetches never 403. Captures the manager (not self) to avoid a cycle.
    private func startCookieRefresh(immediate: Bool) {
        cookieRefreshTask?.cancel()
        let manager = attestationManager
        let filename = selectedTrack.filename
        cookieRefreshTask = Task {
            if immediate {
                try? await manager.refreshStreamAccess(for: filename)
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.cookieRefreshInterval)
                if Task.isCancelled { break }
                try? await manager.refreshStreamAccess(for: filename)
            }
        }
    }

    private func stopCookieRefresh() {
        cookieRefreshTask?.cancel()
        cookieRefreshTask = nil
    }

    // MARK: - Now Playing / remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.isPlaying = true
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.isPlaying = false
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.isPlaying.toggle()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.stepTrack(by: 1) ? .success : .commandFailed
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.stepTrack(by: -1) ? .success : .commandFailed
        }
    }

    // Moves selection within the enabled (picker) tracks. Setting selectedTrackID
    // triggers the lofi reload via ContentView's onChange.
    @discardableResult
    private func stepTrack(by offset: Int) -> Bool {
        let tracks = availableTracks
        guard !tracks.isEmpty,
              let idx = tracks.firstIndex(where: { $0.id == selectedTrackID })
        else { return false }
        let next = (idx + offset + tracks.count) % tracks.count
        selectedTrackID = tracks[next].id
        updateNowPlaying()
        return true
    }

    private func updateNowPlaying() {
        let track = selectedTrack
        let airport = airports[currentAirportIndex]

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: "lofi atc — \(airport.code)",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]

        if let icon = loadAppIcon() {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadAppIcon() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last
        else { return nil }
        return UIImage(named: name)
    }

    // MARK: - Track selection

    /// Selects the track at a position within `availableTracks` (the picker wheel order).
    func selectTrack(atAvailablePosition pos: Int) {
        let tracks = availableTracks
        guard tracks.indices.contains(pos) else { return }
        selectedTrackID = tracks[pos].id
    }

    /// Adds/removes a track from the wheel. Keeps at least one enabled, and moves
    /// selection to a remaining track if the selected one is turned off.
    func toggleTrack(_ id: UUID) {
        if enabledTrackIDs.contains(id) {
            guard enabledTrackIDs.count > 1 else { return }
            enabledTrackIDs.remove(id)
            if selectedTrackID == id {
                selectedTrackID = availableTracks.first?.id ?? selectedTrackID
            }
        } else {
            enabledTrackIDs.insert(id)
        }
    }

    // MARK: - Settings preview

    /// Plays just the given track's lofi audio; tapping the active one again stops it.
    /// Routes through App Attest so the gated /hls/ endpoint serves the preview.
    func toggleLofiPreview(trackID: UUID) {
        if activePreview == .lofi(trackID) { stopPreview(); return }
        stopPreview()
        guard let track = allTracks.first(where: { $0.id == trackID }) else { return }
        activePreview = .lofi(trackID)
        Task { @MainActor in
            do {
                let url = try await attestationManager.requestStreamURL(for: track.filename)
                // The user may have toggled the preview off while we were fetching.
                guard activePreview == .lofi(trackID) else { return }
                let player = AVPlayer(url: url)
                player.volume = 1.0
                player.play()
                previewLofiPlayer = player
            } catch {
                print("[AudioManager] preview attestation failed: \(error)")
                if activePreview == .lofi(trackID) { activePreview = nil }
            }
        }
    }

    /// Plays just the ATC audio (regular, for the current airport); tapping again stops it.
    func toggleATCPreview(filter: String) {
        if activePreview == .atc(filter) { stopPreview(); return }
        stopPreview()
        let filename = airports[currentAirportIndex].atcFilename
        guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3", subdirectory: "Audio")
                     ?? Bundle.main.url(forResource: filename, withExtension: "mp3")
        else { return }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = 1.0
        player?.prepareToPlay()
        player?.play()
        previewATCPlayer = player
        activePreview = .atc(filter)
    }

    func stopPreview() {
        previewLofiPlayer?.pause()
        previewLofiPlayer = nil
        previewATCPlayer?.stop()
        previewATCPlayer = nil
        activePreview = nil
    }

    private func updateVolumes() {
        atcPlayer?.volume = min(1.0, Float(balance) * 4.0) * fadeMultiplier
        lofiPlayer?.volume = Float(1.0 - balance) * fadeMultiplier
    }

    // MARK: - Fade

    private static let fadeDuration: TimeInterval = 1.5
    private static let fadeSteps = 30

    // Starts both players muted and ramps them up to their mix targets.
    func fadeInPlayback() {
        let atcTarget = min(1.0, Float(balance) * 4.0)
        let lofiTarget = Float(1.0 - balance)

        atcPlayer?.volume = 0
        lofiPlayer?.volume = 0

        if atcPlayer == nil { loadATC() }
        atcPlayer?.play()
        if lofiPlayer == nil {
            Task { await loadAndPlayLofi() }
        } else {
            lofiPlayer?.play()
            startCookieRefresh(immediate: true)
        }

        suppressObservers = true
        isPlaying = true
        suppressObservers = false

        atcPlayer?.setVolume(atcTarget, fadeDuration: Self.fadeDuration)
        fadeLofiVolume(to: lofiTarget)
    }

    // Smoothly crossfades the mix to a new balance instead of snapping volumes.
    func fadeToBalance(_ newBalance: Double) {
        suppressObservers = true
        balance = newBalance
        suppressObservers = false

        let atcTarget = min(1.0, Float(newBalance) * 4.0)
        let lofiTarget = Float(1.0 - newBalance)

        atcPlayer?.setVolume(atcTarget, fadeDuration: Self.fadeDuration)
        fadeLofiVolume(to: lofiTarget)
    }

    // AVPlayer has no built-in volume ramp, so step it manually on a timer.
    private func fadeLofiVolume(to target: Float) {
        lofiFadeTimer?.invalidate()

        guard let player = lofiPlayer else { return }

        let startVolume = player.volume
        let interval = Self.fadeDuration / Double(Self.fadeSteps)
        let delta = (target - startVolume) / Float(Self.fadeSteps)
        var step = 0

        lofiFadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            step += 1
            if step >= Self.fadeSteps {
                player.volume = target
                timer.invalidate()
                self?.lofiFadeTimer = nil
            } else {
                player.volume = startVolume + delta * Float(step)
            }
        }
    }

    // MARK: - Sleep timer

    func startSleepTimer(minutes: Int) {
        let total = Double(minutes) * 60
        sleepEndDate = Date().addingTimeInterval(total)
        sleepRemaining = total
        sleepActive = true

        sleepTicker?.invalidate()
        // .common mode so the countdown keeps ticking during scrolls/gestures.
        let ticker = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sleepTick()
        }
        RunLoop.main.add(ticker, forMode: .common)
        sleepTicker = ticker
    }

    func cancelSleepTimer() {
        sleepTicker?.invalidate()
        sleepTicker = nil
        fadeTicker?.invalidate()
        fadeTicker = nil
        sleepEndDate = nil
        sleepActive = false
        sleepRemaining = 0
        fadeMultiplier = 1.0
        updateVolumes()
    }

    private func sleepTick() {
        guard let end = sleepEndDate else { return }
        let remaining = max(0, end.timeIntervalSinceNow)
        sleepRemaining = remaining
        if remaining <= 0 {
            sleepTicker?.invalidate()
            sleepTicker = nil
            fadeOutAndPause(duration: 4)
        }
    }

    private func fadeOutAndPause(duration: TimeInterval) {
        let steps = max(1, Int(duration / 0.05))
        var step = 0
        fadeTicker?.invalidate()
        let ticker = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            self.fadeMultiplier = max(0, 1.0 - Float(step) / Float(steps))
            self.updateVolumes()
            if step >= steps {
                timer.invalidate()
                self.fadeTicker = nil
                self.isPlaying = false   // didSet → pausePlayback()
                self.cancelSleepTimer()  // resets fadeMultiplier + clears state
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        fadeTicker = ticker
    }
}
