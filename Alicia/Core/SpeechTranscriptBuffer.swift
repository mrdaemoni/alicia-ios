import Foundation

/// Speech may return only the newest utterance after a pause. Keep earlier
/// timestamped words while allowing the current hypothesis to be corrected.
/// Provisional segment timing cannot establish an earlier, separate utterance.
struct SpeechTranscriptBuffer {
    struct Word {
        var text: String
        var start: Double
        var duration: Double
    }
    private(set) var words: [Word] = []
    private(set) var committed: [String] = []
    private(set) var needsReview = false
    /// Words before the latest callback's hypothesis came from earlier spans.
    /// Keep that boundary even if this callback has unresolved segment timing.
    private var hypothesisStart = 0

    var text: String {
        (committed + [words.map(\.text).joined(separator: " ")])
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    mutating func receive(_ next: [Word]) {
        guard !next.isEmpty else { return } // An empty partial cannot erase speech.
        guard next.allSatisfy({ $0.start.isFinite && $0.duration.isFinite && $0.start >= 0 && $0.duration >= 0 }),
              zip(next, next.dropFirst()).allSatisfy({ $0.0.start <= $0.1.start }) else {
            needsReview = true
            return
        }
        let start = next[0].start
        if let oldEnd = words.last.map({ $0.start + $0.duration }),
           let nextEnd = next.last.map({ $0.start + $0.duration }),
           nextEnd + 1 < oldEnd {
            // A late/regressed partial is ambiguous; preserve the longer capture
            // and expose review instead of silently discarding whole sentences.
            needsReview = true
            return
        }
        // A partial can give every word timestamp/duration zero, then supply
        // the same phrase with real timing. Those zeros do not prove that the
        // phrase ended before the revision began. Replace that whole hypothesis
        // instead of prepending it; older independently timed spans can remain.
        let positioned = words.dropFirst(hypothesisStart).allSatisfy { $0.duration > 0 }
        let eligible = positioned ? words[...] : words.prefix(hypothesisStart)
        let preceding = eligible.prefix { $0.start + $0.duration <= start + 0.001 && $0.start < start }
        hypothesisStart = preceding.count
        words = Array(preceding) + next
    }

    mutating func finishRequest() {
        let value = words.map(\.text).joined(separator: " ")
        if !value.isEmpty { committed.append(value) }
        words = []
        hypothesisStart = 0
    }
}
