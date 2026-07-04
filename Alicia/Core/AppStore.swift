import SwiftUI
import Observation
import AVFoundation

@MainActor
@Observable
final class AppStore {
    // Content
    var messages: [Message] = SampleData.messages
    var thoughts: [Thought] = []
    var tracks: [Track] = []
    var gallery: [Artwork] = []
    var health: [HealthMetric] = []

    // Player state (simulated — see Studio README note to wire real audio)
    var nowPlaying: Track?
    var isPlaying = false
    var progress: Double = 0        // 0...1 through the current track

    private let service: AliciaService
    private var ticker: Task<Void, Never>?

    init(service: AliciaService) {
        self.service = service
        Task { await load() }
    }

    func load() async {
        async let t = service.thoughts()
        async let tr = service.tracks()
        async let g = service.gallery()
        async let h = service.health()
        (thoughts, tracks, gallery, health) = await (t, tr, g, h)
    }

    // MARK: Talk
    func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        messages.append(Message(sender: .me, text: clean))
        let idx = messages.count
        messages.append(Message(sender: .alicia, text: ""))
        Task {
            for await token in service.stream(clean) {
                if messages.indices.contains(idx) { messages[idx].text += token }
            }
        }
    }

    // MARK: Studio player
    // Real playback (AVPlayer) when the track carries a backend URL;
    // the simulated ticker remains the fallback for sample data.
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func play(_ track: Track) {
        if nowPlaying?.id != track.id { progress = 0 }
        nowPlaying = track
        isPlaying = true
        if let f = track.fileName, f.hasPrefix("http"), let url = URL(string: f) {
            startPlayer(url: url)
        } else {
            stopPlayer()
            startTicker()
        }
    }

    func togglePlay() {
        guard nowPlaying != nil else { return }
        isPlaying.toggle()
        if let player {
            isPlaying ? player.play() : player.pause()
        } else {
            isPlaying ? startTicker() : ticker?.cancel()
        }
    }

    private func startPlayer(url: URL) {
        ticker?.cancel()
        stopPlayer()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let d = self.nowPlaying?.duration, d > 0 else { return }
                self.progress = min(1, time.seconds / d)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
        p.play()
    }

    private func stopPlayer() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
    }

    func next() {
        guard let current = nowPlaying,
              let i = tracks.firstIndex(of: current) else { return }
        play(tracks[(i + 1) % tracks.count])
    }

    func previous() {
        guard let current = nowPlaying,
              let i = tracks.firstIndex(of: current) else { return }
        play(tracks[(i - 1 + tracks.count) % tracks.count])
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                guard self.isPlaying, let d = self.nowPlaying?.duration, d > 0 else { continue }
                self.progress = min(1, self.progress + 0.5 / d)
                if self.progress >= 1 { self.next() }
            }
        }
    }

    // MARK: Canvas
    func requestComplement(for title: String) {
        Task {
            let art = await service.complement(title)
            gallery.insert(art, at: 0)
        }
    }
}
