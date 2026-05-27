//
//  AudioManager.swift
//  ZenATC
//

import AVFoundation
import Observation

let backendBaseURL = URL(string: "https://zenatc.bedson.tech")!

@Observable
final class AudioManager {
    var isPlaying = false {
        didSet { isPlaying ? startPlayback() : pausePlayback() }
    }

    // balance: 0 = full lofi (headphones), 1 = full ATC (airplane)
    var balance: Double = 0.5 {
        didSet { updateVolumes() }
    }

    var currentAirportIndex = 0
    var selectedTrackIndex = 0

    // ATC: local bundle file, loops natively via AVAudioPlayer
    private var atcPlayer: AVAudioPlayer?
    // Lofi: VOD HLS stream — starts instantly, downloads ahead, loops from cache
    private var lofiPlayer: AVPlayer?
    private var lofiItem: AVPlayerItem?
    private var lofiLoopObserver: Any?

    private let airports = Airport.all
    private let tracks = LofiTrack.all
    private let attestationManager = AttestationManager(backendBaseURL: backendBaseURL)

    init() {
        configureSession()
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
    }

    private func pausePlayback() {
        atcPlayer?.pause()
        lofiPlayer?.pause()
    }

    func reloadATC() {
        atcPlayer?.stop()
        atcPlayer = nil
        loadATC()
        if isPlaying {
            updateVolumes()
            atcPlayer?.play()
        }
    }

    func reloadLofi() {
        tearDownLofi()
        Task { await loadAndPlayLofi() }
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
}
