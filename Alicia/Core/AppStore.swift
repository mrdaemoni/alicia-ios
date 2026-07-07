import SwiftUI
import Observation
import AVFoundation
import MediaPlayer
import WidgetKit

@MainActor
@Observable
final class AppStore {
    // Content
    var messages: [Message] = SampleData.messages
    var thoughts: [Thought] = []
    var tracks: [Track] = []
    var gallery: [Artwork] = []
    var health: [HealthMetric] = []

    // Player state — real AVPlayer for backend tracks, ticker fallback for
    // sample data (see "Studio player" below)
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
        async let fs = service.featured()
        async let qt = service.quote()
        async let ar = service.archetypes()
        async let kn = service.knowing()
        async let sy = service.syntheses()
        async let hc = service.homeContext()
        (thoughts, tracks, gallery, health) = await (t, tr, g, h)
        homeContext = await hc ?? homeContext
        (thinkingMode, walkWords) = await m
        greeting = await gr ?? greeting
        featured = await fs ?? featured
        quote = await qt ?? quote
        let stats = await ar
        if !stats.isEmpty { archetypeStats = stats }
        knowing = await kn ?? knowing
        let shelf = await sy
        if !shelf.isEmpty { syntheses = shelf }
        if thinkerNetwork == nil {
            thinkerNetwork = await service.thinkers()
        }
        publishWidgetCache()
        Task { await refreshEpisodeThinkers() }
        let pro = await p
        if !pro.isEmpty {
            proactiveFeed = pro
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

    // MARK: home-screen widget
    /// The widget reads a shared app-group cache — no network of its own.
    /// Refresh it (and the timelines) whenever the app loads fresh data.
    private func publishWidgetCache() {
        guard let shared = UserDefaults(suiteName: "group.com.myalicia.app") else { return }
        if let greeting, !greeting.isEmpty {
            shared.set(greeting, forKey: "widget.greeting")
        }
        if let featured {
            shared.set(featured.title, forKey: "widget.featuredTitle")
        }
        if let latest = proactiveFeed.first {
            shared.set(String(latest.text.prefix(200)), forKey: "widget.note")
        }
        if let quote {
            shared.set("“" + quote.text + "”", forKey: "widget.quote")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: live proactive polling
    // While the app runs, check her feed every minute: new items join the
    // timeline as whispers, update the Us card, and post a banner. This is
    // what makes her feel PRESENT on the phone — BG refresh alone (see
    // ProactiveNotifier) fires far too rarely on a dev-signed build.
    private var proactivePoll: Task<Void, Never>?

    func startProactivePolling() {
        proactivePoll?.cancel()
        proactivePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.pollProactive()
            }
        }
    }

    func stopProactivePolling() {
        proactivePoll?.cancel()
        proactivePoll = nil
    }

    private func pollProactive() async {
        let fresh = await service.proactive(limit: 6)
        guard !fresh.isEmpty else { return }
        let known = Set(proactiveFeed.map(\.id))
        let new = fresh.filter { !known.contains($0.id) }
        proactiveFeed = fresh
        guard !new.isEmpty else { return }
        for m in new.reversed() {
            messages.append(Message(
                sender: .alicia, text: m.text, date: m.date,
                proactiveLabel: [m.kind.replacingOccurrences(of: "_", with: " "),
                                 m.archetype]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "),
                proactiveID: m.id))
            await ProactiveNotifier.notify(m)
        }
        ProactiveNotifier.markSeen(fresh)
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
    /// Her recent proactive messages — Us reply card + Alicia-tab detail.
    var proactiveFeed: [ProactiveMessage] = []
    /// The synthesis of the day (Us page reading card).
    var featured: FeaturedSynthesis?
    /// Quote of the moment (Us page; rotates thrice daily).
    var quote: (text: String, author: String)?
    /// Live loop state per voice from /api/archetypes (empty offline).
    var archetypeStats: [ArchetypeStat] = []
    /// What she knows of Hector — three horizons (Us page eye card).
    var knowing: KnowingState?
    /// The Knowledge tab's synthesis shelf + thinker network.
    var syntheses: [FeaturedSynthesis] = []
    var thinkerNetwork: ThinkerNetwork?
    /// Deep link into the Knowledge tab's thinker detail.
    var pendingThinker: String?
    /// Which room the Knowledge tab shows: 0 = the shelf, 1 = the thinkers.
    var knowledgeSegment = 0
    /// The whole arc since her birth (fetched when the sheet opens).
    var timeline: [TimelineDay] = []

    // MARK: the loops (Us tab home context)
    /// Season arc → episode trail → today's episode → knowledge cards.
    var homeContext: HomeContext?

    /// Verdicts already given this run (card id → verdict), persisted so a
    /// relaunch doesn't re-ask for cards he already judged today.
    var cardVerdicts: [String: String] =
        (UserDefaults.standard.dictionary(forKey: "alicia.cardVerdicts")
            as? [String: String]) ?? [:]

    /// Verdict on one knowledge card — optimistic UI, then the backend
    /// (card-ordering weights + shared daily signal). A follow-up why note
    /// re-posts the same verdict carrying the note.
    func giveCardFeedback(_ card: HomeContext.Card, verdict: String,
                          note: String = "") {
        cardVerdicts[card.id] = verdict
        // Card ids embed the episode label, so old entries go stale, not
        // wrong — prune to keep the defaults dictionary small.
        if cardVerdicts.count > 200 { cardVerdicts = [card.id: verdict] }
        UserDefaults.standard.set(cardVerdicts, forKey: "alicia.cardVerdicts")
        Task {
            _ = await service.cardFeedback(cardID: card.id, kind: card.kind,
                                           verdict: verdict, note: note)
        }
    }

    /// The playable track for an episode label ("S11E08"), if the library
    /// has it — bridges today's-episode card to the Studio player.
    func track(forLabel label: String) -> Track? {
        tracks.first(where: { $0.label == label })
    }

    func loadTimeline() async {
        if timeline.isEmpty {
            timeline = await service.timeline()
        }
    }

    /// Thinkers mentioned in the shownotes of the active/suggested episode
    /// — the knowledge currently in Hector's ears.
    var episodeThinkers: [Thinker] = []

    func refreshEpisodeThinkers() async {
        guard let net = thinkerNetwork else { return }
        guard let track = nowPlaying ?? suggestedTracks.first else { return }
        let notes = await episodeNotes(for: track)
        guard !notes.isEmpty else { episodeThinkers = []; return }
        let lower = notes.lowercased()
        episodeThinkers = net.thinkers.filter { t in
            let last = t.name.split(separator: " ").last.map(String.init) ?? t.name
            return last.count > 3 && lower.contains(last.lowercased())
        }
        .prefix(3).map { $0 }
    }

    /// Voices ranked by the REAL loop when the backend answers (7-day
    /// attributions, effectiveness tiebreak); falls back to counting the
    /// local proactive feed in mock/offline mode.
    var rankedArchetypes: [(name: String, count: Int)] {
        if !archetypeStats.isEmpty {
            return archetypeStats.map { (name: $0.name, count: $0.count) }
        }
        var counts: [String: Int] = [:]
        for m in proactiveFeed where !m.archetype.isEmpty {
            counts[m.archetype.lowercased(), default: 0] += 1
        }
        for t in thoughts where Archetypes.all[t.tag.lowercased()] != nil {
            counts[t.tag.lowercased(), default: 0] += 1
        }
        return Archetypes.order
            .map { (name: $0, count: counts[$0] ?? 0) }
            .sorted { $0.count > $1.count }
    }

    /// Landing multiplier for a voice ("1.09×"), when the loop has one.
    func effectiveness(of name: String) -> Double? {
        archetypeStats.first(where: { $0.name == name.lowercased() })?.effectiveness
    }

    /// Today's listening: her active pick first, then the next unheard
    /// episodes of the newest season.
    var suggestedTracks: [Track] {
        var out: [Track] = []
        if let pick = tracks.first(where: { $0.mood.contains("today's pick") }) {
            out.append(pick)
        }
        for t in tracks where !out.contains(t) {
            out.append(t)
            if out.count >= 3 { break }
        }
        return Array(out.prefix(3))
    }

    /// Deep link: jump to Studio and start the episode.
    func playFromHome(_ track: Track) {
        selectedSection = .studio
        play(track)
    }
    /// Programmatic tab switching (Dialogue chips → Alicia tab).
    var selectedSection: AppSection = .us
    /// Which proactive card the Alicia tab should scroll to on arrival
    /// (set by a Dialogue whisper tap; cleared after the scroll).
    var pendingMindFocusID: String?
    /// The Dialogue composer owns the keyboard — the editorial tab bar
    /// steps aside while it's up.
    var composerFocused = false
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

    /// React to a proactive message directly by id (Alicia-tab cards that
    /// may not have a timeline twin).
    func reactToProactive(id: String, emoji: String) {
        if let i = messages.firstIndex(where: { $0.proactiveID == id }) {
            messages[i].reaction = emoji
        }
        Task { await service.react(proactiveID: id, emoji: emoji) }
    }

    /// Reply to a proactive message from the Us page. The backend lands it
    /// in every layer (Tier-3 capture, shared history, memory) and answers;
    /// the exchange also joins the Dialogue timeline.
    func replyToProactive(_ proactive: ProactiveMessage, text: String) async -> String? {
        let reply = await service.reply(proactiveID: proactive.id, text: text)
        messages.append(Message(sender: .me, text: text))
        if let reply, !reply.isEmpty {
            messages.append(Message(sender: .alicia, text: reply))
        }
        return reply
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
    private var stallObserver: NSObjectProtocol?

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
        isScrubbing = false   // a scrub abandoned mid-switch froze the bar
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        // Long episodes over the tailnet: buffer generously and ride out
        // stalls instead of pausing forever (the "stopped around minute 10"
        // bug — a transient network dip mid-episode).
        item.preferredForwardBufferDuration = 60
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        player = p
        stallObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                // Nudge playback back into motion once the buffer refills.
                self.player?.playImmediately(atRate: self.playbackRate)
            }
        }
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

    /// Spiral artwork for the system player, rendered once. With artwork +
    /// full metadata the lock screen / Dynamic Island shows a real
    /// now-playing card (title, Alicia, series · episode, art) instead of a
    /// bare speaker glyph.
    private static let nowPlayingArtwork: MPMediaItemArtwork? = {
        guard let image = UIImage(named: "ArtSpiral") else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    private func publishNowPlaying() {
        guard let track = nowPlaying else { return }
        let album = [track.series.isEmpty ? "Made for Hector" : track.series,
                     track.label ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: "Alicia",
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork = Self.nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress * track.duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed(_ seconds: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func stopPlayer() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = nil
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

    // MARK: Canvas co-creation
    /// Her stroke layers, oldest first — rendered beneath PencilKit so
    /// Hector keeps drawing on top of her, she on top of him.
    var canvasOverlays: [UIImage] = []
    var cocreateCaption: String?
    var isCocreating = false

    /// Send the flattened canvas; she draws from where the pencil stopped.
    func aliciaContinues(composite: UIImage, canvasSize: CGSize,
                         anchor: CGPoint?) async {
        guard let png = composite.pngData(), !isCocreating else { return }
        isCocreating = true
        defer { isCocreating = false }
        guard let result = await service.cocreate(
            image: png, width: Int(canvasSize.width), height: Int(canvasSize.height),
            anchor: anchor)
        else {
            cocreateCaption = "couldn't reach her — try again"
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: result.overlay)
            if let image = UIImage(data: data) {
                canvasOverlays.append(image)
                cocreateCaption = result.caption
            }
        } catch {
            cocreateCaption = "couldn't fetch her strokes — try again"
        }
    }

    func clearCanvasCocreation() {
        canvasOverlays = []
        cocreateCaption = nil
    }
}
