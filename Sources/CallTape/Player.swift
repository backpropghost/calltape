import Foundation
import AVFoundation
import Combine

/// One shared audio player for the whole app, so only a single recording plays at
/// a time and the UI can reflect what's playing.
final class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayer()

    @Published private(set) var currentURL: URL?
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0   // 0...1
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTime: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    /// Toggle play/pause for a file. Starting a new file replaces the current one.
    func toggle(_ url: URL) {
        if currentURL == url, let player {
            if player.isPlaying { pause() } else { resume() }
        } else {
            play(url)
        }
    }

    func play(_ url: URL) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            currentURL = url
            duration = player.duration
            isPlaying = true
            startTicking()
        } catch {
            Log.error("Playback failed: \(error.localizedDescription)")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.invalidate()
    }

    func resume() {
        player?.play()
        isPlaying = true
        startTicking()
    }

    func stop() {
        player?.stop()
        player = nil
        ticker?.invalidate()
        isPlaying = false
        progress = 0
        currentTime = 0
        currentURL = nil
    }

    /// Play `url` (starting it if needed) and jump to a specific time, for tapping a
    /// transcript timestamp.
    func playAndSeek(_ url: URL, to seconds: Double) {
        if currentURL != url { play(url) }
        guard let player else { return }
        player.currentTime = max(0, min(seconds, player.duration))
        if !player.isPlaying { player.play(); startTicking() }
        isPlaying = true
        updateProgress()
    }

    /// Seek to a 0...1 position.
    func seek(to fraction: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(1, fraction)) * player.duration
        updateProgress()
    }

    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func updateProgress() {
        guard let player else { return }
        currentTime = player.currentTime
        duration = player.duration
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in self?.stop() }
    }
}

func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
