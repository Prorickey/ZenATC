//
//  AudioManager.swift
//  ZenATC
//

import AVFoundation
import Observation

// Change this to your Mac's LAN IP when testing on a physical device.
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

    private var lofiPlayer: AVPlayer?
    private var atcPlayer: AVPlayer?

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
        if lofiPlayer == nil { loadLofi() }
        if atcPlayer == nil { loadATC() }
        updateVolumes()
        lofiPlayer?.play()
        atcPlayer?.play()
    }

    private func pausePlayback() {
        lofiPlayer?.pause()
        atcPlayer?.pause()
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

    func reloadATC() {
        atcPlayer?.pause()
        atcPlayer = nil
        loadATC()
        if isPlaying {
            updateVolumes()
            atcPlayer?.play()
        }
    }

    private func loadLofi() {
        let filename = tracks[selectedTrackIndex].filename
        guard let url = URL(string: "\(backendBaseURL)/radio/\(filename)/index.m3u8") else { return }
        lofiPlayer = AVPlayer(url: url)
    }

    private func loadATC() {
        let filename = airports[currentAirportIndex].atcFilename
        guard let url = URL(string: "\(backendBaseURL)/radio/\(filename)/index.m3u8") else { return }
        atcPlayer = AVPlayer(url: url)
    }

    private func updateVolumes() {
        lofiPlayer?.volume = Float(1.0 - balance)
        atcPlayer?.volume = min(1.0, Float(balance) * 4.0)
    }
}
