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

    /// True once the sample seed has been replaced by her real proactive
    /// feed — never clobber a conversation in progress on refresh.
    private var liveTimelineSeeded = false

    func load() async {
        async let t = service.thoughts()
        async let tr = service.tracks()
        async let g = service.gallery()
        async let h = service.health()
        async let p = service.proactive(limit: 6)
        (thoughts, tracks, gallery, health) = await (t, tr, g, h)
        let pro = await p
        if !pro.isEmpty {
            ProactiveNotifier.markSeen(pro)
            if !liveTimelineSeeded {
                // Open on what she's actually been saying, oldest first.
                liveTimelineSeeded = true
                messages = pro.reversed().map { m in
                    Message(sender: .alicia, text: m.text, date: m.date,
                            proactiveLabel: [m.kind.replacingOccurrences(of: "_", with: " "),
                                             m.archetype]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                }
            }
        }
    }

    // MARK: Talk
    /// Whether Alicia's replies also arrive as voice notes.
    var voiceReplies = UserDefaults.standard.bool(forKey: "alicia.voiceReplies") {
        didSet { UserDefaults.standard.set(voiceReplies, forKey: "alicia.voiceReplies") }
    }

    func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        messages.append(Message(sender: .me, text: clean))
        let idx = messages.count
        messages.append(Message(sender: .alicia, text: ""))
        Task {
            for await event in service.stream(clean, voice: voiceReplies) {
                guard messages.indices.contains(idx) else { break }
                switch event {
                case .token(let t):   messages[idx].text += t
                case .voice(let url): messages[idx].voiceURL = url
                case .done(let mid):  messages[idx].messageID = mid
                }
            }
        }
    }

    /// React to one of Alicia's replies. Optimistic UI; the backend feeds
    /// it into her reaction→archetype learning loop.
    func react(to message: Message, with emoji: String) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[i].reaction = emoji
        guard let mid = message.messageID else { return }
        Task { await service.react(messageID: mid, emoji: emoji) }
    }

    // Voice-note playback (separate from the Studio player so a voice note
    // never interrupts a podcast position).
    private var voicePlayer: AVPlayer?

    func playVoiceNote(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        voicePlayer = AVPlayer(url: url)
        voicePlayer?.play()
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
    /// `image` is the canvas as PNG — when present, Alicia sees what was
    /// actually drawn (vision pass on the backend) before replying.
    func requestComplement(for title: String, image: Data? = nil) {
        Task {
            let art = await service.complement(title, imageData: image)
            gallery.insert(art, at: 0)
        }
    }
}
