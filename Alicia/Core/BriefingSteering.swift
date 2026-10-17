import Foundation

// CL-20261015-steerable-briefing — the steerable morning briefing.
//
// The backend prepares the briefing as segments, each with up to three
// validated altitudes (L+1 higher, L0, L−1 lower) whose sentences carry the
// claims-ledger items they say. This file holds the payload models and the
// pure planner. The planner mirrors `skills/briefing_steering.py` exactly
// (interpretation table and the entry-sentence rule), so a press the server
// cannot answer in time is applied by the same rule and shown in the same
// words. Nothing here touches the network, the player or the clock.

/// One spoken sentence and the ledger items it carries. Offsets are unicode
/// scalars into its chunk's text; times are measured seconds inside that chunk.
struct BriefingSentence: Codable, Hashable {
    var text: String = ""
    var ledger_ids: [String] = []
    var chunk: Int = -1
    var start_char: Int = -1
    var end_char: Int = -1
    var start: Double = -1
    var end: Double = -1
    var timed: Bool = false

    init(text: String = "", ledger_ids: [String] = [], chunk: Int = -1, start_char: Int = -1, end_char: Int = -1,
         start: Double = -1, end: Double = -1, timed: Bool = false) {
        self.text = text; self.ledger_ids = ledger_ids; self.chunk = chunk; self.start_char = start_char
        self.end_char = end_char; self.start = start; self.end = end; self.timed = timed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        ledger_ids = try c.decodeIfPresent([String].self, forKey: .ledger_ids) ?? []
        chunk = try c.decodeIfPresent(Int.self, forKey: .chunk) ?? -1
        start_char = try c.decodeIfPresent(Int.self, forKey: .start_char) ?? -1
        end_char = try c.decodeIfPresent(Int.self, forKey: .end_char) ?? -1
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? -1
        end = try c.decodeIfPresent(Double.self, forKey: .end) ?? -1
        timed = try c.decodeIfPresent(Bool.self, forKey: .timed) ?? false
    }
}

struct BriefingVariantChunk: Codable, Hashable {
    var url: String = ""
    var duration: Double = 0
    var text: String = ""
    var sha256: String = ""
    var timing_status: String = "unavailable"
    var cues: [NarrationCue] = []
    var speech_backend: String = ""

    init(url: String = "", duration: Double = 0, text: String = "", sha256: String = "",
         timing_status: String = "unavailable", cues: [NarrationCue] = [], speech_backend: String = "") {
        self.url = url; self.duration = duration; self.text = text; self.sha256 = sha256
        self.timing_status = timing_status; self.cues = cues; self.speech_backend = speech_backend
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256) ?? ""
        timing_status = try c.decodeIfPresent(String.self, forKey: .timing_status) ?? "unavailable"
        cues = try c.decodeIfPresent([NarrationCue].self, forKey: .cues) ?? []
        speech_backend = try c.decodeIfPresent(String.self, forKey: .speech_backend) ?? ""
    }
}

struct BriefingVariant: Codable, Hashable {
    var level: Int = 0
    var sha256: String = ""
    var text: String = ""
    var spoken_text: String = ""
    var duration: Double = 0
    var word_count: Int = 0
    var chunks: [BriefingVariantChunk] = []
    var sentences: [BriefingSentence] = []

    init(level: Int, sha256: String, text: String, spoken_text: String, duration: Double, word_count: Int,
         chunks: [BriefingVariantChunk], sentences: [BriefingSentence]) {
        self.level = level; self.sha256 = sha256; self.text = text; self.spoken_text = spoken_text
        self.duration = duration; self.word_count = word_count; self.chunks = chunks; self.sentences = sentences
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        spoken_text = try c.decodeIfPresent(String.self, forKey: .spoken_text) ?? ""
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        word_count = try c.decodeIfPresent(Int.self, forKey: .word_count) ?? 0
        chunks = try c.decodeIfPresent([BriefingVariantChunk].self, forKey: .chunks) ?? []
        sentences = try c.decodeIfPresent([BriefingSentence].self, forKey: .sentences) ?? []
    }

    /// Playable only with measured chunks and at least one sentence.
    var isPlayable: Bool {
        !chunks.isEmpty && !sentences.isEmpty && chunks.allSatisfy { $0.duration.isFinite && $0.duration > 0 }
    }
}

struct BriefingSegment: Codable, Hashable, Identifiable {
    var id: String = ""
    var index: Int = 0
    var theme: String = ""
    var ledger_ids: [String] = []
    var levels: [Int] = []
    var variants: [BriefingVariant] = []

    init(id: String, index: Int, theme: String, ledger_ids: [String], variants: [BriefingVariant]) {
        self.id = id; self.index = index; self.theme = theme; self.ledger_ids = ledger_ids
        self.variants = variants; self.levels = variants.map(\.level)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? ""
        ledger_ids = try c.decodeIfPresent([String].self, forKey: .ledger_ids) ?? []
        levels = try c.decodeIfPresent([Int].self, forKey: .levels) ?? []
        variants = try c.decodeIfPresent([BriefingVariant].self, forKey: .variants) ?? []
    }

    func variant(_ level: Int) -> BriefingVariant? {
        variants.first { $0.level == level && $0.isPlayable }
    }
}

struct BriefingSteeringInfo: Codable, Hashable {
    struct Study: Codable, Hashable {
        var study_active: Bool = false
        var study_week: Int = 0
        var study_day: Int = 0
        var study_start: String = ""
        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            study_active = try c.decodeIfPresent(Bool.self, forKey: .study_active) ?? false
            study_week = try c.decodeIfPresent(Int.self, forKey: .study_week) ?? 0
            study_day = try c.decodeIfPresent(Int.self, forKey: .study_day) ?? 0
            study_start = try c.decodeIfPresent(String.self, forKey: .study_start) ?? ""
        }
    }
    struct Cue: Codable, Hashable { var url: String = ""; var duration: Double = 0 }
    struct Validation: Codable, Hashable { var session_id: String = ""; var verdict: String = ""; var path_status: String = ""; var at: String = "" }

    var enabled = false
    var arm = "off"
    var study = Study()
    var commands: [String] = []
    var again_previous_within_seconds: Double = 1.5
    var remote_commands_default = false
    var cues: [String: Cue] = [:]
    var validations: [Validation] = []
    var lines: [String: String] = [:]
    var reason = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        arm = try c.decodeIfPresent(String.self, forKey: .arm) ?? "off"
        study = try c.decodeIfPresent(Study.self, forKey: .study) ?? Study()
        commands = try c.decodeIfPresent([String].self, forKey: .commands) ?? []
        again_previous_within_seconds = try c.decodeIfPresent(Double.self, forKey: .again_previous_within_seconds) ?? 1.5
        remote_commands_default = try c.decodeIfPresent(Bool.self, forKey: .remote_commands_default) ?? false
        cues = try c.decodeIfPresent([String: Cue].self, forKey: .cues) ?? [:]
        validations = try c.decodeIfPresent([Validation].self, forKey: .validations) ?? []
        lines = try c.decodeIfPresent([String: String].self, forKey: .lines) ?? [:]
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }

    /// The fixed fallback wording, identical to the backend's defaults.
    static let defaultLines: [String: String] = [
        "higher": "From higher up, starting with the next sentence",
        "lower": "Closer in, starting with the next sentence",
        "again": "Again, from the start of that sentence",
        "higher_limit": "Already as high as it goes",
        "lower_limit": "Already as close in as it goes",
        "partial": "Changed where a version exists; this part has only one",
        "after_higher": "The whole briefing again, from higher up",
        "after_lower": "The whole briefing again, closer in",
        "not_applied": "Not changed. These controls open when the briefing ends this week",
        "not_applied_during": "Not changed. This week the controls work while it plays",
        "unavailable": "Not changed. This briefing has only one version",
        "higher_missing": "Not changed. The rest has no higher version",
        "lower_missing": "Not changed. The rest has no closer version",
        "nothing_left": "Not changed. That was the end",
    ]

    func line(_ key: String) -> String { lines[key] ?? Self.defaultLines[key] ?? "" }

    /// The visible arm indicator, in plain words.
    var armLabel: String {
        let week = study.study_active && study.study_week > 0 ? " · WEEK \(study.study_week)" : ""
        switch arm {
        case "during": return "STEER WHILE IT PLAYS" + week
        case "after": return "STEER WHEN IT ENDS" + week
        default: return ""
        }
    }
}

enum SteerCommand: String, Codable, CaseIterable {
    case higher, lower, again
    var title: String {
        switch self { case .higher: return "HIGHER"; case .lower: return "LOWER"; case .again: return "AGAIN" }
    }
}

extension MorningBriefing {
    /// Segment-aware playback applies only when every segment has a playable L0
    /// and the day's arm isn't off; otherwise the legacy single track plays.
    var isSteerable: Bool {
        guard let steering, steering.enabled, steering.arm != "off", !segments.isEmpty else { return false }
        return segments.allSatisfy { $0.variant(0) != nil }
    }
}

/// Where a steer takes effect, as the server (or the same local rule) said.
struct SteerEffect: Codable, Hashable {
    var segment_id: String = ""
    var resume_sentence_index: Int = 0
    var after_segment_id: String? = nil
    var after_sentence_index: Int? = nil
    var level: Int = 0
    var replay: Bool? = nil
    var previous_within_seconds: Double? = nil
}

/// Record 2 of the event model: what Alicia took the press to mean.
struct SteerInterpretation: Codable, Hashable {
    var arm: String = "off"
    var arm_matches_claim = true
    var level_requested = 0
    var level_chosen = 0
    var change = "not_applied"   // level_changed, no_change_at_limit, replay, not_applied
    var reason = ""
    var effective_from: SteerEffect? = nil
    var fallback_segments: [String] = []
    var text = ""
    var cue_id = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        arm = try c.decodeIfPresent(String.self, forKey: .arm) ?? "off"
        arm_matches_claim = try c.decodeIfPresent(Bool.self, forKey: .arm_matches_claim) ?? true
        level_requested = try c.decodeIfPresent(Int.self, forKey: .level_requested) ?? 0
        level_chosen = try c.decodeIfPresent(Int.self, forKey: .level_chosen) ?? 0
        change = try c.decodeIfPresent(String.self, forKey: .change) ?? "not_applied"
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        // The server sends {} when there is no effect.
        let effect = try? c.decodeIfPresent(SteerEffect.self, forKey: .effective_from)
        effective_from = (effect?.segment_id.isEmpty ?? true) ? nil : effect
        fallback_segments = try c.decodeIfPresent([String].self, forKey: .fallback_segments) ?? []
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        cue_id = try c.decodeIfPresent(String.self, forKey: .cue_id) ?? ""
    }
}

/// What one piece of the played path is: which variant, from where.
struct BriefingPiece: Hashable {
    var segmentID: String
    var level: Int
    var variantSHA: String
    /// Index into the variant's chunks; -1 for a spoken cue.
    var chunkIndex: Int
    /// The first sentence (variant index) this piece starts at.
    var fromSentence: Int
    /// Scalar range of the chunk text this piece speaks.
    var textStart: Int
    var textEnd: Int
    /// The stretch this piece belongs to: the variant from `stretchSentence` on.
    var stretchSentence: Int
    /// Set on the first piece a steer produced, so its consequence names the event.
    var eventID: String = ""
    var cause: String = "initial"
    var isCue: Bool { chunkIndex < 0 }
}

/// One stretch of what actually played (the heard path's unit).
struct BriefingPathStep: Codable, Hashable {
    var segment_id: String
    var level: Int
    var variant_sha256: String
    var from_sentence_index: Int
    var seconds: Double = 0
    var event_id: String = ""

    var key: String { "\(segment_id)|\(level)|\(variant_sha256)|\(from_sentence_index)" }
}

enum BriefingPlanner {
    /// Within this much of a sentence's end, a press applies after the next one.
    static let minimumLead: Double = 0.35
    /// Lead-in kept before a sentence's first measured word.
    static let entryPad: Double = 0.08
    /// Tail kept after a sentence's last measured word, at most.
    static let exitPad: Double = 0.15

    // MARK: the rules shared with the backend

    /// Mirror of `briefing_steering.entry_sentence`. nil means: next segment.
    static func entrySentence(_ segment: BriefingSegment, from: Int, after: Int, to: Int) -> Int? {
        guard let old = segment.variant(from) ?? segment.variant(0), let new = segment.variant(to) else { return nil }
        var heard = Set<String>()
        for sentence in old.sentences.prefix(max(0, after) + 1) { heard.formUnion(sentence.ledger_ids) }
        let unheard = Set(segment.ledger_ids).subtracting(heard)
        guard !unheard.isEmpty else { return nil }
        return new.sentences.firstIndex { !unheard.isDisjoint(with: $0.ledger_ids) } ?? 0
    }

    /// Mirror of `briefing_steering.interpret`. Pure.
    static func interpret(segments: [BriefingSegment], steering: BriefingSteeringInfo, command: SteerCommand,
                          segmentID: String, sentence: Int, levelBefore: Int, phase: String) -> SteerInterpretation {
        var base = SteerInterpretation()
        base.arm = steering.arm
        base.level_requested = levelBefore
        base.level_chosen = levelBefore
        func refused(_ reason: String, _ key: String, requested: Int? = nil) -> SteerInterpretation {
            var r = base; r.change = "not_applied"; r.reason = reason; r.text = steering.line(key)
            if let requested { r.level_requested = requested }
            return r
        }
        guard !segments.isEmpty else { return refused("single_version", "unavailable") }
        if steering.arm == "off" { return refused("steering_off", "unavailable") }
        if phase == "during" && steering.arm == "after" { return refused("arm_after", "not_applied") }
        if phase == "after_end" && steering.arm == "during" { return refused("arm_during", "not_applied_during") }
        guard let position = segments.firstIndex(where: { $0.id == segmentID }) else { return refused("unknown_segment", "unavailable") }
        let segment = segments[position]
        if command == .again {
            var r = base; r.change = "replay"; r.text = steering.line("again"); r.cue_id = "again"
            r.effective_from = SteerEffect(segment_id: segmentID, resume_sentence_index: sentence, level: levelBefore,
                                           previous_within_seconds: steering.again_previous_within_seconds)
            return r
        }
        let step = command == .higher ? 1 : -1
        let requested = max(-1, min(1, levelBefore + step))
        base.level_requested = requested
        if requested == levelBefore {
            var r = base; r.change = "no_change_at_limit"; r.reason = "at_limit"; r.cue_id = "limit"
            r.text = steering.line(step > 0 ? "higher_limit" : "lower_limit")
            return r
        }
        let missing = step > 0 ? "higher_missing" : "lower_missing"
        let has = segments.map { $0.variant(requested) != nil }
        if phase == "after_end" {
            guard has.contains(true) else { return refused("level_unavailable", missing, requested: requested) }
            var r = base; r.change = "level_changed"; r.level_chosen = requested; r.cue_id = command.rawValue
            r.text = steering.line(step > 0 ? "after_higher" : "after_lower")
            r.effective_from = SteerEffect(segment_id: segments[0].id, resume_sentence_index: 0, level: requested, replay: true)
            r.fallback_segments = zip(segments, has).filter { !$0.1 }.map { $0.0.id }
            return r
        }
        var target: Int? = nil, resume = 0
        if has[position], let entry = entrySentence(segment, from: levelBefore, after: sentence, to: requested) {
            target = position; resume = entry
        }
        if target == nil {
            target = (position + 1 ..< segments.count).first { has[$0] }
            resume = 0
        }
        guard let target else {
            let current = segment.variant(levelBefore) ?? segment.variant(0)
            if position == segments.count - 1, sentence == (current?.sentences.count ?? 1) - 1 {
                return refused("nothing_left", "nothing_left", requested: requested)
            }
            return refused("level_unavailable", missing, requested: requested)
        }
        var r = base; r.change = "level_changed"; r.level_chosen = requested; r.cue_id = command.rawValue
        r.text = steering.line(has[position] ? (step > 0 ? "higher" : "lower") : "partial")
        r.effective_from = SteerEffect(segment_id: segments[target].id, resume_sentence_index: resume,
                                       after_segment_id: segmentID, after_sentence_index: sentence, level: requested)
        r.fallback_segments = (target + 1 ..< segments.count).filter { !has[$0] }.map { segments[$0].id }
        return r
    }

    /// Whether a reading changes what plays: a new altitude or a replay. A
    /// press that would only say "Not changed" or "Already as high as it goes"
    /// changes nothing, so its button is drawn faded and can't be pressed.
    static func changes(_ reading: SteerInterpretation) -> Bool {
        reading.change == "level_changed" || reading.change == "replay"
    }

    // MARK: building the played path

    /// The variant that plays for a segment at a dial: the dial if validated, else L0.
    static func playable(_ segment: BriefingSegment, dial: Int) -> BriefingVariant? {
        segment.variant(dial) ?? segment.variant(0)
    }

    static func scalars(_ text: String, _ a: Int, _ b: Int) -> String {
        let s = Array(text.unicodeScalars)
        let lo = max(0, min(a, s.count)), hi = max(lo, min(b, s.count))
        return String(String.UnicodeScalarView(s[lo..<hi]))
    }

    /// Materialize one piece: the chunk's audio from `clipStart` to `clipEnd`,
    /// its text from `textStart` to `textEnd`, cues shifted to the piece.
    static func chunk(_ variant: BriefingVariant, segment: BriefingSegment, chunkIndex k: Int, url: URL,
                      fromSentence: Int, stretchSentence: Int, clipStart: Double = 0, clipEnd: Double? = nil,
                      textStart: Int = 0, textEnd: Int? = nil, eventID: String = "", cause: String = "initial") -> SpeechChunk {
        let source = variant.chunks[k]
        let total = source.text.unicodeScalars.count
        let a = max(0, min(textStart, total)), b = max(a, min(textEnd ?? total, total))
        let end = min(clipEnd ?? source.duration, source.duration)
        let cues = source.timing_status == "ready" ? source.cues.compactMap { cue -> NarrationCue? in
            guard cue.start_char >= a, cue.end_char <= b, cue.start >= clipStart - 0.001, cue.end <= end + 0.05 else { return nil }
            return NarrationCue(start: max(0, cue.start - clipStart), end: max(0.001, cue.end - clipStart), text: cue.text,
                                start_char: cue.start_char - a, end_char: cue.end_char - a)
        } : []
        var out = SpeechChunk(url: url, duration: max(0.05, end - clipStart), text: scalars(source.text, a, b), cues: cues,
                              timingStatus: cues.isEmpty ? "unavailable" : "ready", speechBackend: source.speech_backend)
        out.clipStart = clipStart
        out.clipEnd = clipEnd
        out.piece = BriefingPiece(segmentID: segment.id, level: variant.level, variantSHA: variant.sha256, chunkIndex: k,
                                  fromSentence: fromSentence, textStart: a, textEnd: b, stretchSentence: stretchSentence,
                                  eventID: eventID, cause: cause)
        return out
    }

    /// Where a variant can be entered at sentence `j`: its chunk, the clip start,
    /// the text start, and the sentence actually entered. An untimed sentence is
    /// entered at its chunk's start (a little may repeat; nothing is skipped).
    static func entry(_ variant: BriefingVariant, sentence j: Int, includePrefix: Bool = false) -> (chunk: Int, clip: Double, text: Int, sentence: Int) {
        let j = max(0, min(j, variant.sentences.count - 1))
        let s = variant.sentences[j]
        guard s.chunk >= 0, s.chunk < variant.chunks.count else { return (0, 0, 0, 0) }
        let first = variant.sentences.firstIndex { $0.chunk == s.chunk } ?? j
        // A segment heard from its start keeps any spoken prefix (segment 1's title).
        if j == first && (s.start_char <= 0 || includePrefix) { return (s.chunk, 0, 0, j) }
        if s.timed && s.start >= 0 {
            let prior = j > 0 && variant.sentences[j - 1].chunk == s.chunk && variant.sentences[j - 1].timed
                ? variant.sentences[j - 1].end : 0
            return (s.chunk, max(prior, max(0, s.start - entryPad)), max(0, s.start_char), j)
        }
        return (s.chunk, 0, 0, first)
    }

    /// Pieces for one segment's variant from sentence `j` to its end.
    static func pieces(_ segment: BriefingSegment, variant: BriefingVariant, fromSentence j: Int,
                       resolve: (String) -> URL?, eventID: String = "", cause: String = "initial",
                       includePrefix: Bool = false) -> [SpeechChunk] {
        let place = entry(variant, sentence: j, includePrefix: includePrefix)
        var out: [SpeechChunk] = []
        for k in place.chunk ..< variant.chunks.count {
            guard let url = resolve(variant.chunks[k].url) else { continue }
            let first = k == place.chunk
            let starts = variant.sentences.firstIndex { $0.chunk == k } ?? place.sentence
            out.append(chunk(variant, segment: segment, chunkIndex: k, url: url,
                             fromSentence: first ? place.sentence : starts, stretchSentence: place.sentence,
                             clipStart: first ? place.clip : 0, textStart: first ? place.text : 0,
                             eventID: first ? eventID : "", cause: first ? cause : "initial"))
        }
        return out
    }

    /// The path from segment `index` (at sentence `sentence`) to the end, at `dial`.
    static func path(_ segments: [BriefingSegment], dial: Int, fromSegment index: Int, sentence: Int = 0,
                     resolve: (String) -> URL?, eventID: String = "", cause: String = "initial") -> [SpeechChunk] {
        var out: [SpeechChunk] = []
        for i in max(0, index) ..< segments.count {
            guard let variant = playable(segments[i], dial: dial) else { continue }
            let first = i == index
            let from = first ? sentence : 0
            out += pieces(segments[i], variant: variant, fromSentence: from, resolve: resolve,
                          eventID: first ? eventID : "", cause: first ? cause : "initial", includePrefix: from == 0)
        }
        return out
    }

    /// The sentence playing at `time` (seconds inside chunk `k` of the variant).
    static func sentence(at time: Double, chunk k: Int, in variant: BriefingVariant) -> Int {
        let inChunk = variant.sentences.indices.filter { variant.sentences[$0].chunk == k }
        guard let first = inChunk.first else { return 0 }
        var current = first
        for i in inChunk where variant.sentences[i].timed && variant.sentences[i].start <= time + 0.01 { current = i }
        return current
    }

    /// Where a press at `time` (in chunk `k`) takes effect: after `sentence`, at
    /// file time `cut` in the same chunk, or at the chunk's natural end (`cut` nil).
    static func switchPoint(_ variant: BriefingVariant, chunk k: Int, time: Double) -> (sentence: Int, cut: Double?) {
        let inChunk = variant.sentences.indices.filter { variant.sentences[$0].chunk == k }
        guard !inChunk.isEmpty else { return (variant.sentences.count - 1, nil) }
        var s = sentence(at: time, chunk: k, in: variant)
        while true {
            let row = variant.sentences[s]
            let isLast = s == inChunk.last
            guard row.timed, !isLast else { return (isLast ? s : inChunk.last!, nil) }
            let next = variant.sentences[s + 1]
            let gap = next.timed ? max(0, next.start - row.end) : exitPad * 2
            let cut = row.end + min(exitPad, gap / 2)
            if cut - time >= minimumLead { return (s, cut) }
            s += 1
        }
    }

    /// Again: the sentence to replay, given how far into the current one he is.
    static func againTarget(_ variant: BriefingVariant, chunk k: Int, time: Double, within: Double) -> Int {
        let s = sentence(at: time, chunk: k, in: variant)
        let row = variant.sentences[s]
        if s > 0, row.timed, time - row.start < within { return s - 1 }
        return s
    }

    /// The reader's narration text for a path: segments as paragraphs.
    static func narration(_ chunks: [SpeechChunk]) -> String {
        var out = "", previous: String? = nil
        for chunk in chunks {
            guard let piece = chunk.piece, !piece.isCue, !chunk.text.isEmpty else { continue }
            if let previous { out += previous == piece.segmentID ? " " : "\n\n" }
            out += chunk.text
            previous = piece.segmentID
        }
        return out
    }

    /// A spoken cue as a piece of the path; no text, so it is never "read".
    static func cue(_ id: String, steering: BriefingSteeringInfo, resolve: (String) -> URL?) -> SpeechChunk? {
        guard !id.isEmpty, let cue = steering.cues[id], cue.duration > 0, let url = resolve(cue.url) else { return nil }
        var out = SpeechChunk(url: url, duration: cue.duration)
        out.piece = BriefingPiece(segmentID: "", level: 0, variantSHA: "", chunkIndex: -1, fromSentence: 0,
                                  textStart: 0, textEnd: 0, stretchSentence: 0)
        return out
    }

    // MARK: what a reading does to the path

    enum Action {
        /// Keep the sounding piece (optionally ending it sooner) and replace what follows.
        case replaceFuture(current: SpeechChunk?, tail: [SpeechChunk], immediate: Bool)
        /// Start again from the beginning (after-arm replays, Again at the end).
        case restart([SpeechChunk])
        case none
    }

    /// The consequence of one interpretation, as data: what the reader must do
    /// and the dial afterwards. Pure, so every branch is checked in the harness.
    static func consequence(_ meaning: SteerInterpretation, segments: [BriefingSegment], steering: BriefingSteeringInfo,
                            path: [SpeechChunk], pieceIndex: Int, current: Int, sentence: Int, cut: Double?,
                            fileTime: Double, dial: Int, ended: Bool, eventID: String,
                            resolve: (String) -> URL?) -> (action: Action, dial: Int) {
        guard path.indices.contains(pieceIndex), let piece = path[pieceIndex].piece, !piece.isCue,
              let position = segments.firstIndex(where: { $0.id == piece.segmentID }),
              let variant = segments[position].variant(piece.level) else { return (.none, dial) }
        let seg = segments[position]
        let cueChunk = cue(meaning.cue_id, steering: steering, resolve: resolve).map { [$0] } ?? []

        // The heard part never changes; the sounding piece may only end sooner.
        func clipped(at end: Double, through s: Int) -> SpeechChunk? {
            guard let url = resolve(variant.chunks[piece.chunkIndex].url), variant.sentences.indices.contains(s) else { return nil }
            let row = variant.sentences[s]
            return chunk(variant, segment: seg, chunkIndex: piece.chunkIndex, url: url, fromSentence: piece.fromSentence,
                         stretchSentence: piece.stretchSentence, clipStart: path[pieceIndex].clipStart, clipEnd: end,
                         textStart: piece.textStart, textEnd: row.end_char >= 0 ? row.end_char : nil,
                         eventID: piece.eventID, cause: piece.cause)
        }
        func rest(from index: Int, dial: Int, eventID: String = "", cause: String = "initial") -> [SpeechChunk] {
            Self.path(segments, dial: dial, fromSegment: index, resolve: resolve, eventID: eventID, cause: cause)
        }

        if ended {
            switch meaning.change {
            case "level_changed":
                let next = meaning.level_chosen
                return (.restart(cueChunk + rest(from: 0, dial: next, eventID: eventID, cause: "replay_at_end")), next)
            case "replay":
                return (.restart(cueChunk + pieces(seg, variant: variant, fromSentence: sentence, resolve: resolve,
                                                   eventID: eventID, cause: "replay_at_end")), dial)
            default:
                return (.none, dial)
            }
        }

        switch meaning.change {
        case "level_changed":
            guard let effect = meaning.effective_from,
                  let target = segments.firstIndex(where: { $0.id == effect.segment_id }) else { return (.none, dial) }
            let next = meaning.level_chosen
            if target == position, let resumed = segments[target].variant(next) {
                let tail = cueChunk + pieces(seg, variant: resumed, fromSentence: effect.resume_sentence_index,
                                             resolve: resolve, eventID: eventID, cause: "steer")
                    + rest(from: position + 1, dial: next)
                return (.replaceFuture(current: cut.flatMap { clipped(at: $0, through: sentence) }, tail: tail, immediate: false), next)
            }
            if seg.variant(next) != nil {
                // Everything in this segment was heard: the new level starts after this sentence.
                return (.replaceFuture(current: cut.flatMap { clipped(at: $0, through: sentence) },
                                       tail: cueChunk + rest(from: target, dial: next, eventID: eventID, cause: "steer"),
                                       immediate: false), next)
            }
            // This part has one version: finish it, then the new level where it exists.
            let remaining = Array(path[(pieceIndex + 1)...].prefix { $0.piece?.segmentID == seg.id })
            var later = rest(from: position + 1, dial: next)
            if let first = later.firstIndex(where: { $0.piece?.segmentID == effect.segment_id }) {
                later[first].piece?.eventID = eventID
                later[first].piece?.cause = "steer"
                later.insert(contentsOf: cueChunk, at: first)
            }
            return (.replaceFuture(current: nil, tail: remaining + later, immediate: false), next)
        case "replay":
            let threshold = meaning.effective_from?.previous_within_seconds ?? steering.again_previous_within_seconds
            let target = againTarget(variant, chunk: piece.chunkIndex, time: fileTime, within: threshold)
            let again = pieces(seg, variant: variant, fromSentence: target, resolve: resolve, eventID: eventID, cause: "steer")
            let now = clipped(at: max(path[pieceIndex].clipStart + 0.05, fileTime), through: current)
            return (.replaceFuture(current: now, tail: cueChunk + again + rest(from: position + 1, dial: dial), immediate: true), dial)
        case "no_change_at_limit":
            // Confirm eyes-free at the next boundary; what plays is unchanged.
            guard !cueChunk.isEmpty else { return (.none, dial) }
            var tail = cueChunk
            if sentence + 1 < variant.sentences.count {
                tail += pieces(seg, variant: variant, fromSentence: sentence + 1, resolve: resolve)
            }
            return (.replaceFuture(current: cut.flatMap { clipped(at: $0, through: sentence) },
                                   tail: tail + rest(from: position + 1, dial: dial), immediate: false), dial)
        default:
            return (.none, dial)
        }
    }
}
