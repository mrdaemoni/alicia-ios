import CryptoKit
import AVFoundation
import MediaPlayer
import SwiftUI

/// Anything on screen Hector can press play on.
///
/// `spokenText` is the contract with the backend: `skills/ios_api.py`'s
/// `_reading_text()` builds the cache key from exactly this shape, so a
/// pre-rendered piece is found instead of rendered a second time.
struct Readable: Equatable {
    var title: String
    var body: String
    /// Picks her reading tone on the backend ("synthesis", "thought", …)
    /// — see `STYLE_FOR_KIND` in skills/reading_voice.py.
    var kind: String
    /// A reading already rendered in her voice, handed over in the payload.
    /// Only ever complete readings — the backend won't advertise a partial.
    var speechChunks: [SpeechChunk] = []
    var speechDuration: TimeInterval = 0
    var episodeID: String? = nil
    var stableID: String? = nil
    var textSource: String = ""
    /// Stable identity so re-tapping the same piece resumes instead of
    /// restarting, and so the reader can tell "this card" from "that card".
    var id: String { stableID ?? SHA256.hash(data: Data("\(kind)|\(title)|\(body)".utf8)).map { String(format: "%02x", $0) }.joined() }

    var spokenText: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? b : "\(t).\n\n\(b)"
    }
}

extension String {
    /// What a voice should actually say — the Swift-side mirror of
    /// `_clean_for_tts` in skills/voice_skill.py. Used only for readable text
    /// before the backend supplies the exact cleaned narration.
    var spokenPlainText: String {
        var t = strippedEmojis
        // Wikilinks: [[Books/On Quality/OnQuality-21]] → "OnQuality 21"
        while let open = t.range(of: "[["),
              let close = t.range(of: "]]", range: open.upperBound..<t.endIndex) {
            let target = String(t[open.upperBound..<close.lowerBound])
            let display = (target.split(separator: "|").last
                           ?? target.split(separator: "/").last
                           ?? Substring(target))
            t.replaceSubrange(open.lowerBound..<close.upperBound,
                              with: String(display).replacingOccurrences(of: "-", with: " "))
        }
        // Markdown links: [text](url) → "text"
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1",
                                   options: .regularExpression)
        // Fenced + inline code says nothing useful aloud.
        t = t.replacingOccurrences(of: "```[\\s\\S]*?```", with: "",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: "`", with: "")
        // Heading hashes, emphasis marks, list bullets, rules.
        t = t.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^[-*•·]\s+"#, with: "",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^[-*_]{3,}\s*$"#, with: "",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: "*", with: "")
        t = t.replacingOccurrences(of: "_", with: " ")
        // Collapse the whitespace the strips left behind.
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ",
                                   options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reads the page aloud, in Alicia's own voice.
///
/// The backend renders her voice in chunks that start small
/// (`skills/reading_voice.py`), so the first words arrive in ~10–15s instead
/// of the minutes a whole synthesis takes, and playback then stays ahead of
/// the renderer. This plays that sequence as one continuous track: one scrub
/// bar, one clock, chunk seams inaudible.
///
/// Natural server recordings only. Unavailable audio remains visibly retryable.
@MainActor
@Observable
final class SpeechReader: NSObject {

    enum Voice: Equatable {
        case her         // her rendered m4a chunks
    }

    // MARK: what the UI reads

    /// The queue being listened to. One piece for a tapped page; many for a
    /// playlist — the 20–40 minutes Hector assembles for a drive or a walk.
    private(set) var queueItems: [Readable] = []
    private(set) var queuePosition = 0
    /// The playlist this queue came from, when it came from one.
    private(set) var playlistName: String?

    var hasNext: Bool { queuePosition + 1 < queueItems.count }
    var hasPrevious: Bool { queuePosition > 0 }

    private(set) var current: Readable?
    private(set) var isSpeaking = false
    /// Playback intent stays in isSpeaking; this distinguishes startup/stalling
    /// from samples actually playing. Prepared audio never needs a new render.
    private(set) var isLoadingMedia = false
    private(set) var voice: Voice = .her
    /// Waiting on her first chunk — the bar shows this rather than looking
    /// like a play button that did nothing.
    private(set) var isPreparing = false
    /// Playing, but the tail is still rendering behind us.
    private(set) var isStreaming = false
    var progress: Double = 0            // 0…1 through the whole piece
    private(set) var isScrubbing = false
    var rate: Float = 1.0               // 1× → 1.5× → 2×
    /// Set when a reading genuinely can't be produced, so the UI can say so.
    private(set) var failure: String?

    var isActive: Bool { current != nil }

    /// Whole-piece length: exact once rendered, estimated while streaming
    /// (the backend extrapolates from the rate it has measured so far), so
    /// the scrub bar never grows under the finger.
    private(set) var duration: TimeInterval = 0
    var elapsed: TimeInterval { duration * progress }

    /// Injected by AppStore — the network seam stays out of this class.
    var service: AliciaService?
    /// Called just before a reading starts, so the podcast can step aside.
    var willStartReading: (() -> Void)?
    var episodeProgress: ((String, Double, Double) -> Void)?
    var episodeStopped: ((Bool) -> Void)?

    // MARK: engine state

    private var queue = AVQueuePlayer()
    /// Chunks known so far, in speaking order.
    private var chunks: [SpeechChunk] = []
    /// How many of `chunks` have been handed to the queue player.
    private var queuedCount = 0
    /// Which chunk each queued item is, so progress survives the seams.
    private var indexOfItem: [ObjectIdentifier: Int] = [:]
    private var currentIndex = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var mediaFailureObserver: NSObjectProtocol?
    private var mediaTimeObservation: NSKeyValueObservation?
    private var mediaStatusObservation: NSKeyValueObservation?
    private var itemStatusObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var mediaGeneration = 0
    private var mediaFailed = false
    private var pollTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?

    override init() {
        super.init()
        queue.actionAtItemEnd = .advance
    }

    // MARK: starting and stopping

    /// Press play on a whole queue — a playlist, from a given position.
    ///
    /// Auto-advance across pieces is the point: on a walk or in the car the
    /// phone is in a pocket, so reaching the end of one synthesis must roll
    /// into the next without a tap.
    func play(queue items: [Readable], from index: Int = 0,
              playlist: String? = nil) {
        let items = items.filter { !$0.spokenText.isEmpty }
        guard !items.isEmpty else {
            failure = "There's nothing in this playlist to read."
            return
        }
        let start = min(max(0, index), items.count - 1)
        // Re-pressing play on the piece already sounding just toggles.
        if playlistName == playlist, queueItems.map(\.id) == items.map(\.id),
           queuePosition == start, current != nil {
            toggle()
            return
        }
        stop()
        queueItems = items
        queuePosition = start
        playlistName = playlist
        begin(items[start])
    }

    /// Press play on one piece. Re-pressing the piece already loaded toggles
    /// pause rather than starting it over.
    func read(_ item: Readable) {
        if current?.id == item.id {
            toggle()
            return
        }
        stop()
        queueItems = [item]
        queuePosition = 0
        playlistName = nil
        begin(item)
    }

    /// Move to another piece in the queue, keeping the queue intact.
    func advance(by offset: Int) {
        if current?.episodeID != nil { episodeStopped?(false) }
        let next = queuePosition + offset
        guard queueItems.indices.contains(next) else {
            if next >= queueItems.count { finishQueue() }
            return
        }
        queuePosition = next
        let item = queueItems[next]
        // Tear down the audio but NOT the queue.
        pollTask?.cancel()
        pollTask = nil
        teardownQueue()
        chunks = []
        queuedCount = 0
        currentIndex = 0
        progress = 0
        begin(item)
    }

    func next() { advance(by: 1) }
    func previous() {
        // Like every player: a tap early in a piece goes back, later restarts.
        if elapsed > 5 { seek(to: 0) } else { advance(by: -1) }
    }

    private func begin(_ item: Readable) {
        guard !item.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            failure = "There's nothing here to read."
            return
        }
        willStartReading?()
        current = item
        progress = 0
        failure = nil
        mediaFailed = false
        isLoadingMedia = false
        activateAudioSession()

        if !item.speechChunks.isEmpty {
            // Pre-rendered overnight: her voice from the first second.
            voice = .her
            isStreaming = false
            duration = item.speechDuration
            start(chunks: item.speechChunks)
        } else {
            // Nothing cached — hold the play button in a visible "preparing"
            // state while the lead chunk renders, rather than falling to a
            // voice Hector doesn't want to hear.
            voice = .her
            isPreparing = true
            isStreaming = true
            duration = item.speechDuration
            requestHerVoice(for: item)
        }
        prefetchNext()
        publishNowPlaying()
    }

    func toggle() {
        guard isActive else { return }
        if mediaFailed { retryMedia(); return }
        if failure != nil, let item = current {
            failure = nil; isPreparing = true; isStreaming = true
            requestHerVoice(for: item); return
        }
        // Preparation can be cancelled explicitly with Stop; do not invent playback.
        guard !chunks.isEmpty else { return }
        if isSpeaking {
            if current?.episodeID != nil { episodeStopped?(false) }
            isSpeaking = false; isLoadingMedia = false; queue.pause()
        } else {
            isSpeaking = true; activateAudioSession(); isLoadingMedia = true
            queue.play(); queue.rate = rate
        }
        updateMediaState(generation: mediaGeneration)
        publishNowPlaying()
    }

    func stop() {
        if current?.episodeID != nil { episodeStopped?(false) }
        pollTask?.cancel()
        pollTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        teardownQueue()
        queueItems = []
        queuePosition = 0
        playlistName = nil
        current = nil
        isSpeaking = false
        isLoadingMedia = false
        mediaFailed = false
        isPreparing = false
        isStreaming = false
        progress = 0
        duration = 0
        chunks = []
        queuedCount = 0
        currentIndex = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// 1× → 1.5× → 2× → 1×.
    func cycleRate() {
        rate = rate >= 2.0 ? 1.0 : (rate >= 1.5 ? 2.0 : 1.5)
        if isSpeaking { queue.rate = rate }
        publishNowPlaying()
    }

    /// Jump ±15 seconds through the whole piece, across chunk seams.
    func skip(_ seconds: Double) {
        guard isActive, duration > 0 else { return }
        seek(to: min(1, max(0, (elapsed + seconds) / duration)))
    }

    func scrub(to fraction: Double) {
        isScrubbing = true
        progress = min(1, max(0, fraction))
    }

    func commitScrub() {
        defer { isScrubbing = false }
        guard isActive else { return }
        seek(to: progress)
    }

    // MARK: her voice — one track out of many chunks

    /// Seconds of audio before chunk `index` begins.
    private func offsetOfChunk(_ index: Int) -> TimeInterval {
        chunks.prefix(index).reduce(0) { $0 + $1.duration }
    }

    /// Which chunk a whole-piece position lands in, and how far into it.
    private func locate(_ seconds: TimeInterval) -> (index: Int, offset: TimeInterval) {
        var remaining = max(0, seconds)
        for (i, chunk) in chunks.enumerated() {
            if remaining < chunk.duration || i == chunks.count - 1 {
                return (i, min(remaining, max(0, chunk.duration)))
            }
            remaining -= chunk.duration
        }
        return (0, 0)
    }

    private func seek(to fraction: Double) {
        if current?.episodeID != nil { episodeStopped?(false) }
        progress = min(1, max(0, fraction))
        // Only what's rendered can be sought into; a scrub past the rendered
        // edge lands on the last chunk we actually have.
        let target = locate(duration * progress)
        rebuildQueue(from: target.index, offset: target.offset)
        publishNowPlaying()
    }

    private func start(chunks newChunks: [SpeechChunk]) {
        chunks = newChunks
        if duration <= 0 { duration = chunks.reduce(0) { $0 + $1.duration } }
        rebuildQueue(from: 0, offset: 0)
    }

    /// Rebuild the queue starting at a chunk, seeking into it. Used to begin
    /// playback and to land a scrub.
    private func rebuildQueue(from index: Int, offset: TimeInterval) {
        guard !chunks.isEmpty else { return }
        let start = min(max(0, index), chunks.count - 1)
        detachObservers()
        queue.removeAllItems()
        if queue.status == .failed {
            queue = AVQueuePlayer()
            queue.actionAtItemEnd = .advance
        }
        indexOfItem = [:]
        queuedCount = start
        for i in start..<chunks.count { append(chunkAt: i) }
        currentIndex = start
        attachObservers()
        guard !mediaFailed else { return }
        if offset > 0, let item = queue.currentItem {
            item.seek(to: CMTime(seconds: offset, preferredTimescale: 600),
                      completionHandler: nil)
        }
        isSpeaking = true
        isPreparing = false
        isLoadingMedia = true
        queue.play()
        queue.rate = rate
        updateMediaState(generation: mediaGeneration)
    }

    private func append(chunkAt index: Int) {
        guard !mediaFailed, index < chunks.count else { return }
        let item = AVPlayerItem(url: chunks[index].url)
        // Each chunk is small and +faststart, so a short buffer is plenty.
        item.preferredForwardBufferDuration = 15
        let identity = ObjectIdentifier(item)
        indexOfItem[identity] = index
        let stamp = mediaGeneration
        itemStatusObservations[identity] = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            guard observed.status == .failed else { return }
            Task { @MainActor in
                // The queue may release a failed item before this actor turn.
                self?.mediaDidFail(generation: stamp, itemID: identity)
            }
        }
        if queue.canInsert(item, after: nil) {
            queue.insert(item, after: nil)
            queuedCount = max(queuedCount, index + 1)
        } else {
            mediaDidFail(generation: stamp, itemID: identity)
        }
    }

    private func updateMediaState(generation stamp: Int) {
        guard stamp == mediaGeneration, voice == .her, current != nil else { return }
        if queue.status == .failed || queue.currentItem?.status == .failed {
            mediaDidFail(generation: stamp)
            return
        }
        // A paused player with playback intent can be between play() and its
        // first waiting/playing notification. Keep startup visibly loading.
        isLoadingMedia = !mediaFailed && isSpeaking && queue.timeControlStatus != .playing
    }

    private func mediaDidFail(generation stamp: Int, itemID: ObjectIdentifier? = nil) {
        guard stamp == mediaGeneration, voice == .her, current != nil, !mediaFailed else { return }
        if let itemID, indexOfItem[itemID] == nil { return }
        mediaFailed = true
        queue.pause()
        pollTask?.cancel(); pollTask = nil
        isSpeaking = false; isLoadingMedia = false; isPreparing = false
        failure = "The recording couldn't play. You can retry it."
        if current?.episodeID != nil { episodeStopped?(false) }
        publishNowPlaying()
    }

    private func retryMedia() {
        guard mediaFailed, let item = current, !chunks.isEmpty else { return }
        let target = locate(duration * progress)
        // Rebuilding replaces failed items/player while preserving the logical
        // playlist, position and source. Prepared audio needs no new render.
        mediaFailed = false; failure = nil
        activateAudioSession()
        rebuildQueue(from: target.index, offset: target.offset)
        if isStreaming, !mediaFailed { requestHerVoice(for: item) }
        publishNowPlaying()
    }

    private func attachObservers() {
        let stamp = mediaGeneration
        mediaTimeObservation = queue.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateMediaState(generation: stamp) }
        }
        mediaStatusObservation = queue.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateMediaState(generation: stamp) }
        }
        mediaFailureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let item = note.object as? AVPlayerItem else { return }
                self.mediaDidFail(generation: stamp, itemID: ObjectIdentifier(item))
            }
        }
        timeObserver = queue.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.3, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, stamp == self.mediaGeneration, !self.mediaFailed,
                      !self.isScrubbing else { return }
                if self.duration <= 0, self.chunks.count == 1,
                   let measured = self.queue.currentItem?.duration.seconds, measured.isFinite, measured > 0 {
                    self.duration = measured; self.chunks[0].duration = measured
                }
                guard self.duration > 0 else { return }
                // Keep currentIndex honest: the queue advances on its own at
                // a chunk seam, and progress must not snap back to zero.
                if let item = self.queue.currentItem,
                   let index = self.indexOfItem[ObjectIdentifier(item)] {
                    self.currentIndex = index
                }
                let played = self.offsetOfChunk(self.currentIndex) + time.seconds
                self.progress = min(1, max(0, played / self.duration))
                self.updateNowPlayingElapsed(played)
                if self.queue.timeControlStatus == .playing, let id = self.current?.episodeID {
                    self.episodeProgress?(id, played, Double(self.rate))
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, stamp == self.mediaGeneration, !self.mediaFailed,
                      let item = note.object as? AVPlayerItem,
                      let index = self.indexOfItem[ObjectIdentifier(item)] else { return }
                // The last chunk of a finished reading ends the piece; the
                // last chunk of a still-rendering one just means we've caught
                // up with the renderer.
                if index >= self.chunks.count - 1 {
                    if self.isStreaming {
                        self.isPreparing = true      // waiting on more audio
                    } else {
                        if self.current?.episodeID != nil { self.episodeStopped?(true) }
                        self.finishReading()
                    }
                }
            }
        }
    }

    private func detachObservers() {
        mediaGeneration += 1
        if let timeObserver { queue.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let mediaFailureObserver { NotificationCenter.default.removeObserver(mediaFailureObserver) }
        mediaTimeObservation?.invalidate(); mediaStatusObservation?.invalidate()
        itemStatusObservations.values.forEach { $0.invalidate() }
        itemStatusObservations = [:]
        mediaTimeObservation = nil; mediaStatusObservation = nil; mediaFailureObserver = nil
        timeObserver = nil
        endObserver = nil
    }

    private func teardownQueue() {
        detachObservers()
        queue.pause()
        queue.removeAllItems()
        indexOfItem = [:]
    }

    /// Fold newly-rendered chunks into a reading already in progress.
    private func extend(with newChunks: [SpeechChunk], total: TimeInterval,
                        complete: Bool) {
        guard !mediaFailed, newChunks.count >= chunks.count else { return }
        let hadNone = chunks.isEmpty
        chunks = newChunks
        duration = total > 0 ? total : chunks.reduce(0) { $0 + $1.duration }
        isStreaming = !complete
        if hadNone {
            rebuildQueue(from: 0, offset: 0)        // the lead chunk landed
            return
        }
        for i in queuedCount..<chunks.count { append(chunkAt: i) }
        guard !mediaFailed else { return }
        // We may have run dry waiting for this; get moving again.
        if isPreparing, isSpeaking == false || queue.rate == 0 {
            isPreparing = false
            isSpeaking = true
            isLoadingMedia = true
            queue.play()
            queue.rate = rate
        }
        isPreparing = false
        updateMediaState(generation: mediaGeneration)
    }

    /// Ask the backend for her voice and follow the render until it's done.
    private func requestHerVoice(for item: Readable) {
        guard let service else { narrationUnavailable("Connect to Alicia to prepare this reading."); return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            for attempt in 0..<200 {
                if Task.isCancelled { return }
                let result = await service.requestSpeech(text: item.spokenText,
                                                         kind: item.kind)
                guard !Task.isCancelled, let self, self.current?.id == item.id else { return }
                switch result {
                case .ready(let chunks, let duration):
                    self.extend(with: chunks, total: duration, complete: true)
                    if !chunks.contains(where: { $0.timingStatus == "pending" }) { return }
                case .streaming(let chunks, let duration):
                    self.extend(with: chunks, total: duration, complete: false)
                case .rendering:
                    break
                case .unavailable:
                    self.narrationUnavailable("Her voice is unavailable. Retry when connected.")
                    return
                case .failed:
                    self.narrationUnavailable("This reading could not finish preparing. Please retry.")
                    return
                }
                // Poll fast at first — the lead chunk lands in ~10–15s — then
                // ease off while the tail renders.
                try? await Task.sleep(for: .seconds(attempt < 20 ? 1.5 : 4.0))
            }
            if let self, self.chunks.isEmpty || self.isStreaming {
                self.narrationUnavailable("This reading is still preparing. Please retry shortly.")
            }
        }
    }

    private func narrationUnavailable(_ message: String) {
        queue.pause()
        isSpeaking = false; isLoadingMedia = false; isPreparing = false
        isStreaming = false; failure = message
        if current?.episodeID != nil { episodeStopped?(false) }
        publishNowPlaying()
    }

    var narrationChunks: [SpeechChunk] { chunks }
    var narrationText: String {
        chunks.first(where: { !$0.spokenText.isEmpty })?.spokenText ?? current?.spokenText.spokenPlainText ?? ""
    }
    var focusedChunkIndex: Int? { chunks.indices.contains(currentIndex) ? currentIndex : nil }
    func seekToNarration(seconds: Double) {
        guard seconds.isFinite, duration > 0 else { return }
        seek(to: max(0, min(seconds, chunks.reduce(0) { $0 + $1.duration })) / duration)
    }

    // MARK: finishing

    /// This piece is done. In a playlist that means the next one starts —
    /// the phone is in a pocket on a walk, so silence between pieces would
    /// end the listening session.
    fileprivate func finishReading() {
        if hasNext {
            advance(by: 1)
            return
        }
        finishQueue()
    }

    private func finishQueue() {
        isSpeaking = false
        isLoadingMedia = false
        isPreparing = false
        isStreaming = false
        progress = 1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Warm the NEXT piece while this one plays.
    ///
    /// Adding to a playlist already triggers a render, so this is usually a
    /// cache hit that costs one request. When it isn't — a piece queued
    /// while the backend was down — this is what stops the gap between
    /// tracks being ~15s of silence at the roadside.
    private func prefetchNext() {
        guard hasNext, let service else { return }
        let upcoming = queueItems[queuePosition + 1]
        guard upcoming.speechChunks.isEmpty else { return }   // already have it
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            _ = await service.requestSpeech(text: upcoming.spokenText,
                                            kind: upcoming.kind)
            _ = self
        }
    }

#if DEBUG
    /// Inert visual fixture: no audio, network, playback evidence or user memory.
    func prepareReadingPreview(unavailable: Bool = false) {
        let text = "Enough is a quality of attention.\n\nThe question is not how much you can hold. It is what becomes clear when you give one thing your attention.\n\nLeave room for what you have not understood yet."
        current = Readable(title: "A little room for enough · fixture", body: text, kind: "preview")
        let lead = "Enough is a quality of attention."
        chunks = [SpeechChunk(url: URL(string: "https://fixture.invalid/never-loaded.m4a")!, duration: 30,
            text: text, cues: [NarrationCue(start: 0, end: 1, text: "Enough", start_char: 0, end_char: 6),
                NarrationCue(start: 1, end: 2, text: "is", start_char: 7, end_char: 9),
                NarrationCue(start: 2, end: 3, text: "a", start_char: 10, end_char: 11),
                NarrationCue(start: 3, end: 4, text: "quality", start_char: 12, end_char: 19),
                NarrationCue(start: 4, end: 5, text: "of", start_char: 20, end_char: 22),
                NarrationCue(start: 5, end: 6, text: "attention.", start_char: 23, end_char: lead.unicodeScalars.count)],
            timingStatus: unavailable ? "unavailable" : "ready", spokenText: text)]
        duration = 30; progress = 3.5 / 30
        if unavailable { failure = "Her voice is unavailable. Retry when connected." }
    }
#endif

    // MARK: audio session + lock screen

    private func activateAudioSession() {
        // .spokenAudio ducks other audio the way an audiobook does, and keeps
        // reading when the screen locks (the `audio` background mode).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private static let artwork: MPMediaItemArtwork? = {
        guard let image = UIImage(named: "ArtSpiral") else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    private func publishNowPlaying() {
        guard let item = current else { return }
        // On the lock screen in a car, the album line is where "which of the
        // eight am I on" has to live.
        var album = voice == .her ? "Read aloud" : "Read aloud · stand-in voice"
        if let playlistName, queueItems.count > 1 {
            album = "\(playlistName) · \(queuePosition + 1) of \(queueItems.count)"
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title.isEmpty ? "A reading" : item.title,
            MPMediaItemPropertyArtist: "Alicia",
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isSpeaking ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
        ]
        if let art = Self.artwork { info[MPMediaItemPropertyArtwork] = art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed(_ seconds: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = isSpeaking ? Double(rate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
