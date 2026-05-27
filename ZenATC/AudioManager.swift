//
//  AudioManager.swift
//  ZenATC
//

import AVFoundation
import MediaPlayer
import Observation

let backendBaseURL = URL(string: "https://zenatc.bedson.tech")!

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

    private var suppressObservers = false

    var currentAirportIndex = 0
    var selectedTrackIndex = 0

    // ATC: local bundle file, loops natively via AVAudioPlayer
    private var atcPlayer: AVAudioPlayer?
    // Lofi: VOD HLS stream — starts instantly, downloads ahead, loops from cache
    private var lofiPlayer: AVPlayer?
    private var lofiItem: AVPlayerItem?
    private var lofiLoopObserver: Any?
    private var lofiFadeTimer: Timer?

    private let airports = Airport.all
    private let tracks = LofiTrack.all
    private let attestationManager = AttestationManager(backendBaseURL: backendBaseURL)

    init() {
        configureSession()
        configureRemoteCommands()
    }

    @MainActor
    func preload() async {
        loadATC()

        let filename = tracks[selectedTrackIndex].filename
        let streamURL = await resolveLofiURL(filename: filename)

        tearDownLofi()

        lofiItem = AVPlayerItem(url: streamURL)
        lofiPlayer = AVPlayer(playerItem: lofiItem)
        lofiPlayer?.volume = 0

        lofiLoopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: lofiItem,
            queue: .main
        ) { [weak self] _ in
            self?.lofiPlayer?.seek(to: .zero)
            if self?.isPlaying == true { self?.lofiPlayer?.play() }
        }

        lofiPlayer?.automaticallyWaitsToMinimizeStalling = true
    }

    // MARK: - Private

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
        }
        updateNowPlaying()
    }

    private func pausePlayback() {
        atcPlayer?.pause()
        lofiPlayer?.pause()
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

    // Fetches a signed CDN URL via App Attest, then starts playback.
    //
    // Play-through behaviour:
    //   Pass 1 — AVPlayer streams each 4-second segment from Cloudflare, buffering ahead.
    //   Pass 2+ — segments are in the local URL cache; playback is fully offline.
    @MainActor
    private func loadAndPlayLofi() async {
        let filename = tracks[selectedTrackIndex].filename
        let streamURL = await resolveLofiURL(filename: filename)

        // Tear down any previous state before creating new objects.
        tearDownLofi()

        lofiItem = AVPlayerItem(url: streamURL)
        lofiPlayer = AVPlayer(playerItem: lofiItem)

        // When the track reaches the end, seek back to the beginning and replay.
        // On the second loop all segments should already be in the device's URL
        // cache, so playback restarts without any network requests.
        lofiLoopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: lofiItem,
            queue: .main
        ) { [weak self] _ in
            self?.lofiPlayer?.seek(to: .zero)
            if self?.isPlaying == true { self?.lofiPlayer?.play() }
        }

        updateVolumes()
        if isPlaying { lofiPlayer?.play() }
    }

    private func tearDownLofi() {
        if let obs = lofiLoopObserver {
            NotificationCenter.default.removeObserver(obs)
            lofiLoopObserver = nil
        }
        lofiPlayer?.pause()
        lofiPlayer = nil
        lofiItem = nil
    }

    private func resolveLofiURL(filename: String) async -> URL {
        do {
            return try await attestationManager.requestStreamURL(for: filename)
        } catch {
            print("[AudioManager] attestation failed, using direct URL: \(error)")
            return backendBaseURL.appendingPathComponent("hls/\(filename)/index.m3u8")
        }
    }

    private func updateVolumes() {
        atcPlayer?.volume = min(1.0, Float(balance) * 4.0)
        lofiPlayer?.volume = Float(1.0 - balance)
    }

    private static let fadeDuration: TimeInterval = 1.5
    private static let fadeSteps = 30

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
        }

        suppressObservers = true
        isPlaying = true
        suppressObservers = false

        atcPlayer?.setVolume(atcTarget, fadeDuration: Self.fadeDuration)
        fadeLofiVolume(to: lofiTarget)
        updateNowPlaying()
    }

    func fadeToBalance(_ newBalance: Double) {
        suppressObservers = true
        balance = newBalance
        suppressObservers = false

        let atcTarget = min(1.0, Float(newBalance) * 4.0)
        let lofiTarget = Float(1.0 - newBalance)

        atcPlayer?.setVolume(atcTarget, fadeDuration: Self.fadeDuration)
        fadeLofiVolume(to: lofiTarget)
    }

    // MARK: - Now Playing

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
            let next = (self.selectedTrackIndex + 1) % self.tracks.count
            self.selectedTrackIndex = next
            self.reloadLofi()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let prev = (self.selectedTrackIndex - 1 + self.tracks.count) % self.tracks.count
            self.selectedTrackIndex = prev
            self.reloadLofi()
            return .success
        }
    }

    private func updateNowPlaying() {
        let track = tracks[selectedTrackIndex]
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

    // MARK: - Fade

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
}
