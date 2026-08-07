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
    var speechURL: URL? = nil
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
    /// `_clean_for_tts` in skills/voice_skill.py. Without this the on-device
    /// voice reads asterisks, hashes and wikilink brackets out loud.
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

/// Reads the page aloud. Two engines behind one set of controls:
///
/// * **QUICK** — `AVSpeechSynthesizer`, on-device. Starts on the same
///   runloop tick as the tap, works offline, has no length limit. It is not
///   her voice, and it is never made to sound like it is.
/// * **HER VOICE** — the m4a `skills/reading_voice.py` renders through the
///   same Gemini voice her Telegram voice notes use, played by AVPlayer.
///
/// Pressing play never waits: if her reading isn't cached yet the device
/// voice starts immediately and the backend render is requested in the
/// background. When it lands, `herVoiceReady` goes true and the bar offers
/// the swap — the reader never switches voices mid-sentence on its own,
/// because having the narrator change identity underneath you is worse than
/// finishing in the stand-in.
@MainActor
@Observable
final class SpeechReader: NSObject {

    enum Voice: Equatable {
        case device      // the stand-in
        case her         // the rendered m4a
    }

    // MARK: what the UI reads

    private(set) var current: Readable?
    private(set) var isSpeaking = false
    private(set) var voice: Voice = .device
    /// Her rendering finished while the device voice was reading — the bar
    /// shows the swap affordance.
    private(set) var herVoiceReady = false
    /// True while the backend is still rendering her voice.
    private(set) var herVoiceRendering = false
    var progress: Double = 0            // 0…1 through the piece
    private(set) var isScrubbing = false
    var rate: Float = 1.0               // 1× → 1.5× → 2×
    /// Character range being spoken right now (device voice only) — the
    /// reader highlights it so the eye can follow along.
    private(set) var spokenRange: NSRange?
    /// Set when a reading genuinely can't be produced, so the UI can say so
    /// instead of showing a play button that does nothing.
    private(set) var failure: String?

    var isActive: Bool { current != nil }

    /// Seconds of audio, real for her voice and estimated for the device
    /// voice (which has no duration API — the estimate is only ever used to
    /// draw a clock, never to seek).
    var duration: TimeInterval {
        if voice == .her, herDuration > 0 { return herDuration }
        return Double(spoken.count) / (Self.charsPerSecond * Double(rate))
    }
    var elapsed: TimeInterval { duration * progress }

    /// Injected by AppStore — the network seam stays out of this class.
    var service: AliciaService?
    /// Called just before a reading starts, so the podcast can step aside.
    var willStartReading: (() -> Void)?

    // MARK: engine state

    /// Roughly what an English voice covers per second at 1×. Only used for
    /// the clock and for turning ±15s into a character jump.
    private static let charsPerSecond = 14.5

    private let synth = AVSpeechSynthesizer()
    private var herPlayer: AVPlayer?
    private var herTimeObserver: Any?
    private var herEndObserver: NSObjectProtocol?
    private var herDuration: TimeInterval = 0
    /// The cleaned text both engines work from.
    private var spoken = ""
    /// Where the current utterance began in `spoken` — device-voice progress
    /// is `(utteranceStart + rangeInUtterance) / spoken.count`, so resuming
    /// mid-piece still reports absolute position.
    private var utteranceStart = 0
    private var pollTask: Task<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
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
        let text = item.spokenText.spokenPlainText
        guard !text.isEmpty else {
            failure = "There's nothing here to read."
            return
        }
        willStartReading?()
        current = item
        spoken = text
        progress = 0
        utteranceStart = 0
        failure = nil
        herVoiceReady = false
        herVoiceRendering = false

        activateAudioSession()
        if let url = item.speechURL {
            // Already rendered — she reads it herself from the first second.
            voice = .her
            herDuration = item.speechDuration
            startHerVoice(url: url, from: 0)
        } else {
            voice = .device
            herDuration = 0
            speakOnDevice(from: 0)
            requestHerVoice(for: item)
        }
        publishNowPlaying()
    }

    func toggle() {
        guard isActive else { return }
        if isSpeaking {
            isSpeaking = false
            switch voice {
            case .device: synth.pauseSpeaking(at: .word)
            case .her:    herPlayer?.pause()
            }
        } else {
            isSpeaking = true
            activateAudioSession()
            switch voice {
            case .device:
                // A paused synthesizer resumes; one that finished or was
                // stopped has to be re-primed from where the eye left off.
                if !synth.continueSpeaking() { speakOnDevice(from: charIndex(for: progress)) }
            case .her:
                herPlayer?.play()
                herPlayer?.rate = rate
            }
        }
        publishNowPlaying()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        synth.stopSpeaking(at: .immediate)
        teardownHerPlayer()
        current = nil
        isSpeaking = false
        spokenRange = nil
        progress = 0
        spoken = ""
        utteranceStart = 0
        herVoiceReady = false
        herVoiceRendering = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// 1× → 1.5× → 2× → 1×.
    func cycleRate() {
        rate = rate >= 2.0 ? 1.0 : (rate >= 1.5 ? 2.0 : 1.5)
        switch voice {
        case .her:
            if isSpeaking { herPlayer?.rate = rate }
        case .device:
            // AVSpeechUtterance rate is fixed once speaking starts — re-prime
            // from the current position at the new rate.
            if isSpeaking { speakOnDevice(from: charIndex(for: progress)) }
        }
        publishNowPlaying()
    }

    /// Jump ±15 seconds. The device voice has no timeline, so the same
    /// gesture moves by the number of characters it would have spoken.
    func skip(_ seconds: Double) {
        guard isActive else { return }
        switch voice {
        case .her:
            guard let p = herPlayer, herDuration > 0 else { return }
            let target = min(herDuration, max(0, p.currentTime().seconds + seconds))
            p.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            progress = target / herDuration
        case .device:
            let delta = Int(seconds * Self.charsPerSecond * Double(rate))
            let target = min(spoken.count - 1, max(0, charIndex(for: progress) + delta))
            progress = Double(target) / Double(max(1, spoken.count))
            if isSpeaking { speakOnDevice(from: target) }
        }
        publishNowPlaying()
    }

    func scrub(to fraction: Double) {
        isScrubbing = true
        progress = min(1, max(0, fraction))
    }

    func commitScrub() {
        defer { isScrubbing = false }
        guard isActive else { return }
        switch voice {
        case .her:
            guard let p = herPlayer, herDuration > 0 else { return }
            p.seek(to: CMTime(seconds: progress * herDuration, preferredTimescale: 600))
        case .device:
            if isSpeaking { speakOnDevice(from: charIndex(for: progress)) }
        }
        publishNowPlaying()
    }

    /// Hand the rest of the piece to her real voice, picking up where the
    /// stand-in got to. Only meaningful once `herVoiceReady`.
    func switchToHerVoice() {
        guard let item = current, let url = item.speechURL ?? pendingHerURL else { return }
        let resumeAt = progress
        synth.stopSpeaking(at: .immediate)
        spokenRange = nil
        voice = .her
        herDuration = pendingHerDuration > 0 ? pendingHerDuration : item.speechDuration
        herVoiceReady = false
        startHerVoice(url: url, from: resumeAt)
        publishNowPlaying()
    }

    // MARK: device voice

    private func charIndex(for fraction: Double) -> Int {
        min(max(0, Int(fraction * Double(spoken.count))), max(0, spoken.count - 1))
    }

    /// Speak `spoken` from a character offset, snapped back to a word start
    /// so a resume never begins mid-syllable.
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
        // A touch below default: her register is unhurried, and the pitch
        // ceiling is where synthetic voices sound most synthetic.
        utterance.pitchMultiplier = 0.97
        utterance.postUtteranceDelay = 0
        isSpeaking = true
        synth.speak(utterance)
    }

    /// The closest the device has to her: an English voice at the best
    /// quality installed, preferring the accents her TTS backends use
    /// (Gemini "Aoede" and the en-AU edge-tts fallback) over en-US.
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

    // MARK: her voice

    private var pendingHerURL: URL?
    private var pendingHerDuration: TimeInterval = 0

    private func startHerVoice(url: URL, from fraction: Double) {
        teardownHerPlayer()
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 30
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        herPlayer = p
        herTimeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                // The sidecar duration can be missing (ffprobe absent); fall
                // back to what the player itself reports once it's loaded.
                if self.herDuration <= 0 {
                    let d = p.currentItem?.duration.seconds ?? 0
                    if d.isFinite, d > 0 { self.herDuration = d }
                }
                guard self.herDuration > 0 else { return }
                self.progress = min(1, time.seconds / self.herDuration)
                self.updateNowPlayingElapsed(time.seconds)
            }
        }
        herEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishReading() }
        }
        if fraction > 0, herDuration > 0 {
            p.seek(to: CMTime(seconds: fraction * herDuration, preferredTimescale: 600))
        }
        isSpeaking = true
        p.play()
        p.rate = rate
    }

    private func teardownHerPlayer() {
        if let herTimeObserver { herPlayer?.removeTimeObserver(herTimeObserver) }
        if let herEndObserver { NotificationCenter.default.removeObserver(herEndObserver) }
        herTimeObserver = nil
        herEndObserver = nil
        herPlayer?.pause()
        herPlayer = nil
    }

    /// Ask the backend to render this piece in her voice, then poll.
    /// Everything here is best-effort: the device voice is already reading,
    /// so a failure costs nothing but the swap affordance.
    private func requestHerVoice(for item: Readable) {
        guard let service else { return }
        herVoiceRendering = true
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            // ~5 minutes of patience: a long synthesis is several chunked
            // TTS calls, and Hector is listening the whole time anyway.
            for attempt in 0..<100 {
                if Task.isCancelled { return }
                let result = await service.requestSpeech(text: item.spokenText,
                                                         kind: item.kind)
                guard let self else { return }
                if self.current?.id != item.id { return }   // moved on
                switch result {
                case .ready(let url, let seconds):
                    self.pendingHerURL = url
                    self.pendingHerDuration = seconds
                    self.herVoiceRendering = false
                    if self.voice == .device { self.herVoiceReady = true }
                    return
                case .failed, .unavailable:
                    self.herVoiceRendering = false
                    return
                case .rendering:
                    break
                }
                // Back off from 1.5s to 6s — the first chunks land quickly,
                // after that polling harder just burns battery.
                let delay = attempt < 4 ? 1.5 : (attempt < 12 ? 3.0 : 6.0)
                try? await Task.sleep(for: .seconds(delay))
            }
            self?.herVoiceRendering = false
        }
    }

    // MARK: finishing

    fileprivate func finishReading() {
        isSpeaking = false
        progress = 1
        spokenRange = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: audio session + lock screen

    private func activateAudioSession() {
        // .spokenAudio ducks other audio the way an audiobook does, and
        // keeps reading when the screen locks (the `audio` background mode).
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
            MPMediaItemPropertyAlbumTitle: voice == .her ? "Read aloud" : "Read aloud · stand-in voice",
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

// MARK: - Following along

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
            // Ranges are relative to the current utterance; shift them into
            // the whole piece so highlighting survives a skip or a resume.
            let absolute = NSRange(location: self.utteranceStart + characterRange.location,
                                   length: characterRange.length)
            self.spokenRange = absolute
            let end = Double(absolute.location + absolute.length)
            self.progress = min(1, end / Double(max(1, self.spoken.count)))
            self.updateNowPlayingElapsed(self.elapsed)
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        onMain { [weak self] in
            guard let self, self.voice == .device else { return }
            // Only a genuine run to the end finishes the piece — a skip or a
            // rate change also lands here, having already re-primed the
            // synthesizer with the remainder.
            guard self.synth.isSpeaking == false, self.isSpeaking else { return }
            self.finishReading()
        }
    }
}
