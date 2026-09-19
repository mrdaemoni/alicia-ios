import Foundation

struct NarrationCue: Codable, Hashable {
    var start, end: Double
    var text: String
    var start_char, end_char: Int
}

/// Exact text plus measured alignment. No estimated word clock.
struct NarrationDocument {
    struct Span { var lower, upper: Int; var start, end: Double }
    struct Paragraph: Identifiable {
        var id: Int
        var text: String
        var spans: [Span]
        var chunkStart: Double?
        var chunkEnd: Double?
    }
    var paragraphs: [Paragraph]
    var hasWordTiming: Bool { paragraphs.contains { !$0.spans.isEmpty } }
    init(text: String, chunks: [SpeechChunk]) {
        var located: [(Int, Int, Double, SpeechChunk)] = []
        var cursor = text.startIndex, seconds = 0.0
        for chunk in chunks {
            defer { seconds += max(0, chunk.duration) }
            guard !chunk.text.isEmpty, let range = text.range(of: chunk.text, range: cursor..<text.endIndex) else { continue }
            located.append((text.unicodeScalars.distance(from: text.startIndex, to: range.lowerBound),
                            text.unicodeScalars.distance(from: text.startIndex, to: range.upperBound), seconds, chunk))
            cursor = range.upperBound
        }
        var result: [Paragraph] = [], position = 0
        for raw in text.components(separatedBy: "\n\n") {
            let end = position + raw.unicodeScalars.count
            var spans: [Span] = [], chunkStart: Double?, chunkEnd: Double?
            for (lower, upper, offset, chunk) in located where lower < end && upper > position {
                chunkStart = chunkStart.map { min($0, offset) } ?? offset
                chunkEnd = chunkEnd.map { max($0, offset + chunk.duration) } ?? offset + chunk.duration
                guard chunk.timingStatus == "ready" else { continue }
                let scalars = Array(chunk.text.unicodeScalars)
                var priorEnd = 0.0
                for cue in chunk.cues {
                    guard cue.start.isFinite, cue.end.isFinite, cue.start >= priorEnd,
                          cue.end > cue.start, cue.end <= chunk.duration + 0.05,
                          cue.start_char >= 0, cue.end_char > cue.start_char, cue.end_char <= scalars.count,
                          String(String.UnicodeScalarView(scalars[cue.start_char..<cue.end_char])) == cue.text else { continue }
                    priorEnd = cue.end
                    let a = lower + cue.start_char - position, b = lower + cue.end_char - position
                    guard a >= 0, b <= raw.unicodeScalars.count else { continue }
                    spans.append(Span(lower: a, upper: b, start: offset + cue.start, end: offset + cue.end))
                }
            }
            result.append(Paragraph(id: result.count, text: raw, spans: spans, chunkStart: chunkStart, chunkEnd: chunkEnd))
            position = end + 2
        }
        paragraphs = result
    }
}
