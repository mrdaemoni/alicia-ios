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
    /// Stable identity so re-tapping the same piece resumes instead of
    /// restarting, and so the reader can tell "this card" from "that card".
    var id: String { "\(kind)|\(title)|\(body.count)" }

    var spokenText: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? b : "\(t).\n\n\(b)"
    }
}

extension String {
    /// What a voice should actually say — the Swift-side mirror of
    /// `_clean_for_tts` in skills/voice_skill.py. Only the offline device
    /// voice reads from this; her own renders are cleaned on the backend.
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
/// The on-device synthesizer is a **last resort only**, for when there is no
/// backend at all (mock mode, or the Mac Mini unreachable). Hector's verdict
/// on it was plain — "the standard iOS voice is not nice" — so it is never
/// the default, and the bar says so when it's what you're hearing.
@MainActor
@Observable
final class SpeechReader: NSObject {

    enum Voice: Equatable {
        case her         // her rendered m4a chunks
        case device      // offline last resort
    }

    // MARK: what the UI reads

    private(set) var current: Readable?
    private(set) var isSpeaking = false
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

    // MARK: engine state

    private let queue = AVQueuePlayer()
    /// Chunks known so far, in speaking order.
    private var chunks: [SpeechChunk] = []
    /// How many of `chunks` have been handed to the queue player.
    private var queuedCount = 0
    /// Which chunk each queued item is, so progress survives the seams.
    private var indexOfItem: [ObjectIdentifier: Int] = [:]
    private var currentIndex = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var pollTask: Task<Void, Never>?

    // Offline last resort.
    private let synth = AVSpeechSynthesizer()
    private var spoken = ""
    private var utteranceStart = 0
    /// Only used to draw a clock for the device voice, which has no timeline.
    private static let deviceCharsPerSecond = 14.5

    override init() {
        super.init()
        synth.delegate = self
        queue.actionAtItemEnd = .advance
    }

    // MARK: starting and stopping

    /// Press play on `item`. Re-pressing the piece already loaded toggles
    /// pause rather than starting it over.
    func read(_ item: Readable) {
        if current?.id == item.id {
            toggle()
            return
        }
        stop()
        guard !item.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            failure = "There's nothing here to read."
            return
        }
        willStartReading?()
        current = item
        progress = 0
        failure = nil
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
        publishNowPlaying()
    }

    func toggle() {
        guard isActive else { return }
        if isSpeaking {
            isSpeaking = false
            if voice == .her {
                queue.pause()
            } else {
                synth.pauseSpeaking(at: .word)
            }
        } else {
            isSpeaking = true
            activateAudioSession()
            if voice == .her {
                queue.play()
                queue.rate = rate
            } else if !synth.continueSpeaking() {
                speakOnDevice(from: deviceCharIndex(for: progress))
            }
        }
        publishNowPlaying()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        synth.stopSpeaking(at: .immediate)
        teardownQueue()
        current = nil
        isSpeaking = false
        isPreparing = false
        isStreaming = false
        progress = 0
        duration = 0
        chunks = []
        queuedCount = 0
        currentIndex = 0
        spoken = ""
        utteranceStart = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// 1× → 1.5× → 2× → 1×.
    func cycleRate() {
        rate = rate >= 2.0 ? 1.0 : (rate >= 1.5 ? 2.0 : 1.5)
        if isSpeaking {
            if voice == .her {
                queue.rate = rate
            } else {
                // AVSpeechUtterance rate is fixed once speaking starts.
                speakOnDevice(from: deviceCharIndex(for: progress))
            }
        }
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
        progress = min(1, max(0, fraction))
        guard voice == .her else {
            if isSpeaking { speakOnDevice(from: deviceCharIndex(for: progress)) }
            publishNowPlaying()
            return
        }
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
        indexOfItem = [:]
        queuedCount = start
        for i in start..<chunks.count { append(chunkAt: i) }
        currentIndex = start
        attachObservers()
        if offset > 0, let item = queue.currentItem {
            item.seek(to: CMTime(seconds: offset, preferredTimescale: 600),
                      completionHandler: nil)
        }
        isSpeaking = true
        isPreparing = false
        queue.play()
        queue.rate = rate
    }

    private func append(chunkAt index: Int) {
        guard index < chunks.count else { return }
        let item = AVPlayerItem(url: chunks[index].url)
        // Each chunk is small and +faststart, so a short buffer is plenty.
        item.preferredForwardBufferDuration = 15
        indexOfItem[ObjectIdentifier(item)] = index
        if queue.canInsert(item, after: nil) {
            queue.insert(item, after: nil)
            queuedCount = max(queuedCount, index + 1)
        }
    }

    private func attachObservers() {
        timeObserver = queue.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.3, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing, self.duration > 0 else { return }
                // Keep currentIndex honest: the queue advances on its own at
                // a chunk seam, and progress must not snap back to zero.
                if let item = self.queue.currentItem,
                   let index = self.indexOfItem[ObjectIdentifier(item)] {
                    self.currentIndex = index
                }
                let played = self.offsetOfChunk(self.currentIndex) + time.seconds
                self.progress = min(1, max(0, played / self.duration))
                self.updateNowPlayingElapsed(played)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let item = note.object as? AVPlayerItem,
                      let index = self.indexOfItem[ObjectIdentifier(item)] else { return }
                // The last chunk of a finished reading ends the piece; the
                // last chunk of a still-rendering one just means we've caught
                // up with the renderer.
                if index >= self.chunks.count - 1 {
                    if self.isStreaming {
                        self.isPreparing = true      // waiting on more audio
                    } else {
                        self.finishReading()
                    }
                }
            }
        }
    }

    private func detachObservers() {
        if let timeObserver { queue.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
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
        guard newChunks.count >= chunks.count else { return }
        let hadNone = chunks.isEmpty
        chunks = newChunks
        duration = total > 0 ? total : chunks.reduce(0) { $0 + $1.duration }
        isStreaming = !complete
        if hadNone {
            rebuildQueue(from: 0, offset: 0)        // the lead chunk landed
            return
        }
        for i in queuedCount..<chunks.count { append(chunkAt: i) }
        // We may have run dry waiting for this; get moving again.
        if isPreparing, isSpeaking == false || queue.rate == 0 {
            isPreparing = false
            queue.play()
            queue.rate = rate
            isSpeaking = true
        }
        isPreparing = false
    }

    /// Ask the backend for her voice and follow the render until it's done.
    private func requestHerVoice(for item: Readable) {
        guard let service else { fallBackToDevice(item, reason: nil); return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            for attempt in 0..<200 {
                if Task.isCancelled { return }
                let result = await service.requestSpeech(text: item.spokenText,
                                                         kind: item.kind)
                guard let self, self.current?.id == item.id else { return }
                switch result {
                case .ready(let chunks, let duration):
                    self.extend(with: chunks, total: duration, complete: true)
                    return
                case .streaming(let chunks, let duration):
                    self.extend(with: chunks, total: duration, complete: false)
                case .rendering:
                    break
                case .unavailable:
                    // No backend at all — this is the only case that earns
                    // the device voice.
                    self.fallBackToDevice(item, reason: nil)
                    return
                case .failed:
                    if self.chunks.isEmpty {
                        self.fallBackToDevice(
                            item, reason: "She couldn't voice this one.")
                    } else {
                        self.isStreaming = false     // keep what we have
                    }
                    return
                }
                // Poll fast at first — the lead chunk lands in ~10–15s — then
                // ease off while the tail renders.
                try? await Task.sleep(for: .seconds(attempt < 20 ? 1.5 : 4.0))
            }
        }
    }

    // MARK: offline last resort

    private func fallBackToDevice(_ item: Readable, reason: String?) {
        voice = .device
        isPreparing = false
        isStreaming = false
        failure = reason
        spoken = item.spokenText.spokenPlainText
        guard !spoken.isEmpty else { finishReading(); return }
        duration = Double(spoken.count) / (Self.deviceCharsPerSecond * Double(rate))
        speakOnDevice(from: 0)
        publishNowPlaying()
    }

    private func deviceCharIndex(for fraction: Double) -> Int {
        min(max(0, Int(fraction * Double(spoken.count))), max(0, spoken.count - 1))
    }

    /// Speak from a character offset, snapped back to a word start so a
    /// resume never begins mid-syllable.
    private func speakOnDevice(from index: Int) {
        synth.stopSpeaking(at: .immediate)
        var start = min(max(0, index), max(0, spoken.count - 1))
        let chars = Array(spoken)
        while start > 0, !chars[start - 1].isWhitespace { start -= 1 }
        utteranceStart = start
        let rest = String(chars[start...])
        guard !rest.isEmpty else { finishReading(); return }
        let utterance = AVSpeechUtterance(string: rest)
        utterance.voice = Self.deviceVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
        utterance.pitchMultiplier = 0.97
        isSpeaking = true
        synth.speak(utterance)
    }

    /// The best English voice installed, preferring the accents her TTS
    /// backends use. Still not her — just the least-bad stand-in.
    private static let deviceVoice: AVSpeechSynthesisVoice? = {
        let all = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        let byQuality: (AVSpeechSynthesisVoice) -> Int = { v in
            switch v.quality {
            case .premium:  return 3
            case .enhanced: return 2
            default:        return 1
            }
        }
        let byAccent: (AVSpeechSynthesisVoice) -> Int = { v in
            if v.language.hasPrefix("en-AU") { return 3 }
            if v.language.hasPrefix("en-GB") { return 2 }
            return 1
        }
        let best = all.max { a, b in
            (byQuality(a), byAccent(a)) < (byQuality(b), byAccent(b))
        }
        return best ?? AVSpeechSynthesisVoice(language: "en-AU")
    }()

    // MARK: finishing

    fileprivate func finishReading() {
        isSpeaking = false
        isPreparing = false
        isStreaming = false
        progress = 1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

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
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title.isEmpty ? "A reading" : item.title,
            MPMediaItemPropertyArtist: "Alicia",
            MPMediaItemPropertyAlbumTitle: voice == .her ? "Read aloud"
                                                         : "Read aloud · stand-in voice",
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

// MARK: - Offline voice progress

extension SpeechReader: AVSpeechSynthesizerDelegate {
    /// Delegate callbacks arrive on the synthesizer's own queue, so every one
    /// of them hops to the main actor before touching observable state.
    nonisolated private func onMain(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        onMain { [weak self] in
            guard let self, !self.isScrubbing, self.voice == .device else { return }
            let end = Double(self.utteranceStart + characterRange.location
                             + characterRange.length)
            self.progress = min(1, end / Double(max(1, self.spoken.count)))
            self.updateNowPlayingElapsed(self.elapsed)
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        onMain { [weak self] in
            guard let self, self.voice == .device, self.isSpeaking else { return }
            self.finishReading()
        }
    }
}
