//
//  AudioManager.swift
//  ZenATC
//

import AVFoundation
import Observation

// Change to your Mac's LAN IP when testing on a physical device.
private let backendBaseURL = "http://localhost:8080"

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
    // Lofi: HLS stream from Go backend via AVPlayer
    private var lofiPlayer: AVPlayer?

    private let airports = Airport.all
    private let tracks = LofiTrack.all

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
        if lofiPlayer == nil { loadLofi() }
        updateVolumes()
        atcPlayer?.play()
        lofiPlayer?.play()
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
        lofiPlayer?.pause()
        lofiPlayer = nil
        loadLofi()
        if isPlaying {
            updateVolumes()
            lofiPlayer?.play()
        }
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

    private func loadLofi() {
        let filename = tracks[selectedTrackIndex].filename
        guard let url = URL(string: "\(backendBaseURL)/radio/\(filename)/index.m3u8") else { return }
        lofiPlayer = AVPlayer(url: url)
    }

    private func updateVolumes() {
        atcPlayer?.volume = min(1.0, Float(balance) * 4.0)
        lofiPlayer?.volume = Float(1.0 - balance)
    }
}
