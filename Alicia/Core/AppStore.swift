import SwiftUI
import Observation
import AVFoundation
import MediaPlayer

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
    var playbackRate: Float = 1.0   // 1× → 1.5× → 2× (cycleRate)
    var isScrubbing = false         // finger on the scrub slider

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
        async let m = service.modeState()
        async let gr = service.greeting()
        (thoughts, tracks, gallery, health) = await (t, tr, g, h)
        (thinkingMode, walkWords) = await m
        greeting = await gr ?? greeting
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
                                .joined(separator: " · "),
                            proactiveID: m.id)
                }
            }
        }
    }

    // MARK: Talk
    /// Whether Alicia's replies also arrive as voice notes.
    var voiceReplies = UserDefaults.standard.bool(forKey: "alicia.voiceReplies") {
        didSet { UserDefaults.standard.set(voiceReplies, forKey: "alicia.voiceReplies") }
    }

    // Thinking modes (walk/drive) — shared state machine with Telegram.
    var thinkingMode = "idle"
    var walkWords = 0
    /// Live greeting for the Us page (nil → time-of-day fallback).
    var greeting: String?
    var isWalking: Bool { thinkingMode == "walk" }

    /// Start or end a walk. Her acknowledgment lands in the timeline.
    func toggleWalk() {
        Task {
            let action = isWalking ? "end_walk" : "start_walk"
            if let message = await service.modeAction(action, topic: "") {
                messages.append(Message(sender: .alicia, text: message))
            }
            (thinkingMode, walkWords) = await service.modeState()
        }
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
            // During a walk the backend accumulates instead of chatting —
            // keep the word counter fresh.
            if isWalking { (thinkingMode, walkWords) = await service.modeState() }
        }
    }

    /// Shownotes markdown for an episode (Studio detail page).
    func episodeNotes(for track: Track) async -> String {
        guard let label = track.label else { return "" }
        return await service.episodeNotes(label: label)
    }

    /// React to one of Alicia's messages. Optimistic UI; the backend feeds
    /// chat replies into her reaction→archetype loop and proactive
    /// messages into their circulation entry.
    func react(to message: Message, with emoji: String) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[i].reaction = emoji
        if let mid = message.messageID {
            Task { await service.react(messageID: mid, emoji: emoji) }
        } else if let pid = message.proactiveID {
            Task { await service.react(proactiveID: pid, emoji: emoji) }
        }
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
        // Re-tapping the current track (e.g. opening its detail page)
        // must not restart it from zero.
        if nowPlaying?.id == track.id, player != nil {
            if !isPlaying { isPlaying = true; player?.play() }
            return
        }
        progress = 0
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
            if isPlaying {
                player.play()
                player.rate = playbackRate
            } else {
                player.pause()
            }
        } else {
            isPlaying ? startTicker() : ticker?.cancel()
        }
        publishNowPlaying()
    }

    /// 1× → 1.5× → 2× → 1×.
    func cycleRate() {
        playbackRate = playbackRate >= 2.0 ? 1.0 : (playbackRate >= 1.5 ? 2.0 : 1.5)
        if isPlaying { player?.rate = playbackRate }
        publishNowPlaying()
    }

    /// Live scrub: the slider moves `progress` freely while the finger is
    /// down (the time observer stands back), then `commitScrub` seeks.
    func scrub(to fraction: Double) {
        isScrubbing = true
        progress = min(1, max(0, fraction))
    }

    func commitScrub() {
        defer { isScrubbing = false }
        guard let player, let d = nowPlaying?.duration, d > 0 else { return }
        let target = progress * d
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        updateNowPlayingElapsed(target)
    }

    /// Jump ±15s (player bar's back/forward).
    func skip(_ delta: Double) {
        guard let player, let d = nowPlaying?.duration, d > 0 else { return }
        let target = min(d, max(0, player.currentTime().seconds + delta))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        progress = target / d
        updateNowPlayingElapsed(target)
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
                guard !self.isScrubbing else { return }   // finger owns the bar
                self.progress = min(1, time.seconds / d)
                self.updateNowPlayingElapsed(time.seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
        p.play()
        p.rate = playbackRate
        configureRemoteCommandsOnce()
        publishNowPlaying()
    }

    // MARK: system now-playing (lock screen + Dynamic Island)
    // Publishing MPNowPlayingInfo while playing with the `audio` background
    // mode gives the system media UI — including the Dynamic Island — with
    // artwork-free metadata and working transport controls.
    private var remoteCommandsConfigured = false

    private func configureRemoteCommandsOnce() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.nowPlaying != nil else { return }
                if !self.isPlaying { self.togglePlay() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.nowPlaying != nil else { return }
                if self.isPlaying { self.togglePlay() }
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            MainActor.assumeIsolated {
                guard let self,
                      let e = event as? MPChangePlaybackPositionCommandEvent,
                      let p = self.player else { return }
                p.seek(to: CMTime(seconds: e.positionTime, preferredTimescale: 600))
            }
            return .success
        }
    }

    private func publishNowPlaying() {
        guard let track = nowPlaying else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: "Alicia",
            MPMediaItemPropertyAlbumTitle: track.series.isEmpty
                ? "Made for Hector" : track.series,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
        ]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress * track.duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed(_ seconds: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
