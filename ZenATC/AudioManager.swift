//
//  AudioManager.swift
//  ZenATC
//

import AVFoundation
import Observation

// Change to your Mac's LAN IP when testing on a physical device.
private let backendBaseURL = "http://192.168.1.87:8080"

// A single source previewed in isolation from the Settings screen.
enum AudioPreview: Equatable {
    case lofi(UUID)    // a specific lofi track
    case atc(String)   // an ATC filter (regular audio for now), keyed by filter name
}

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
    // Lofi: HLS stream from Go backend via AVPlayer
    private var lofiPlayer: AVPlayer?

    // Settings preview — plays one source (a single lofi track OR ATC) on its own,
    // separate from the main mix. Exclusive: starting one stops any other.
    private(set) var activePreview: AudioPreview?
    private var previewLofiPlayer: AVPlayer?
    private var previewATCPlayer: AVAudioPlayer?

    private let airports = Airport.all

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
        let filename = selectedTrack.filename
        guard let url = URL(string: "\(backendBaseURL)/radio/\(filename)/index.m3u8") else { return }
        lofiPlayer = AVPlayer(url: url)
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
    func toggleLofiPreview(trackID: UUID) {
        if activePreview == .lofi(trackID) { stopPreview(); return }
        stopPreview()
        guard let track = allTracks.first(where: { $0.id == trackID }),
              let url = URL(string: "\(backendBaseURL)/radio/\(track.filename)/index.m3u8")
        else { return }
        let player = AVPlayer(url: url)
        player.volume = 1.0
        player.play()
        previewLofiPlayer = player
        activePreview = .lofi(trackID)
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
