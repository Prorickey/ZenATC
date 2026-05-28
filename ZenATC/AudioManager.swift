//
//  AudioManager.swift
//  ZenATC
//

import AVFoundation
import Observation

// Change to your Mac's LAN IP when testing on a physical device.
private let backendBaseURL = "http://192.168.1.87:8080"

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

    // Sleep timer — auto fade-out + pause after a chosen duration
    private(set) var sleepActive = false
    private(set) var sleepRemaining: TimeInterval = 0
    private var sleepEndDate: Date?
    private var sleepTicker: Timer?
    private var fadeTicker: Timer?
    private var fadeMultiplier: Float = 1.0

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
        atcPlayer?.volume = min(1.0, Float(balance) * 4.0) * fadeMultiplier
        lofiPlayer?.volume = Float(1.0 - balance) * fadeMultiplier
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
