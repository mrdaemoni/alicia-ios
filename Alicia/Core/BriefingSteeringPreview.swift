#if DEBUG
import AVFoundation
import Foundation

/// Invented, public-safe fixture for `--morning-briefing-steer-preview`
/// (CL-20261015-steerable-briefing). The text is the plan's invented example;
/// there are no real goals, names, vault passages or health data. Audio URLs
/// point at an invalid host and are never loaded: the reader is put into an
/// inert preview state, and word timings are synthetic (0.3 s per word).
@MainActor enum BriefingSteeringPreview {
    static let id = "8a3c6f0e-0f4b-4d6e-9c1a-2b7d5e9f1a00"
    static let title = "Two goals, one set of mornings"

    /// (theme, ledger ids, [level: [(sentence, ledger ids)]])
    private static let content: [(String, [String], [Int: [(String, [String])]])] = [
        ("Mornings", ["s01-l1", "s01-l2", "s01-l3"], [
            1: [("Two of your goals want the same hours this week, and one is more pressed.", ["s01-l1", "s01-l2"]),
                ("The time it needs is my guess, not yours.", ["s01-l3"])],
            0: [("The talk prep and the book edits both want your mornings, and the book's deadline is closer.", ["s01-l1", "s01-l2"]),
                ("My sense of how long the edits take is a rough estimate, not something you told me.", ["s01-l3"])],
            -1: [("Tuesday and Thursday mornings are free, and both the talk prep and the book edits want them.", ["s01-l1"]),
                 ("The book is due first, so its deadline presses harder on those mornings.", ["s01-l2"]),
                 ("The edits need about three of those hours, though that's my estimate, not yours.", ["s01-l3"])],
        ]),
        ("A walk note", ["s02-l1", "s02-l2"], [
            1: [("You asked for lighter mornings, though that comes from a draft that needs review.", ["s02-l1", "s02-l2"])],
            0: [("On yesterday's walk you asked for shorter mornings with fewer threads in them.", ["s02-l1"]),
                ("That comes from a machine draft of the walk, so it still needs your review.", ["s02-l2"])],
            -1: [("Near the end of yesterday's walk you said the mornings felt long and asked for fewer threads in each one.", ["s02-l1"]),
                 ("Those words come from a machine draft of the recording, so read it and correct it before we treat it as settled.", ["s02-l2"])],
        ]),
        ("Invitation", ["s03-l1"], [
            1: [("Which morning goes to the book first?", ["s03-l1"])],
            0: [("So here is one question for today.", []), ("Which free morning do you want to give to the book first?", ["s03-l1"])],
            -1: [("So here is one question for today, with the calendar in front of you.", []),
                 ("Of the free mornings, Tuesday or Thursday, which one do you want to give to the book first?", ["s03-l1"])],
        ]),
    ]

    private static func variant(_ segment: Int, level: Int, sentences: [(String, [String])]) -> BriefingVariant {
        let body = sentences.map(\.0).joined(separator: " ")
        let spoken = segment == 0 ? "\(title).\n\n\(body)" : body
        let scalars = Array(spoken.unicodeScalars)
        // Words by scalar offset, 0.3 s each, the way measured cues arrive.
        var cues: [NarrationCue] = [], i = 0, t = 0.0
        while i < scalars.count {
            guard CharacterSet.alphanumerics.contains(scalars[i]) else { i += 1; continue }
            var j = i
            while j < scalars.count, CharacterSet.alphanumerics.contains(scalars[j]) || scalars[j] == "'" { j += 1 }
            cues.append(NarrationCue(start: t, end: t + 0.25, text: String(String.UnicodeScalarView(scalars[i..<j])),
                                     start_char: i, end_char: j))
            t += 0.3; i = j
        }
        var rows: [BriefingSentence] = [], cursor = spoken.startIndex
        for (text, ledger) in sentences {
            guard let range = spoken.range(of: text, range: cursor..<spoken.endIndex) else { continue }
            let a = spoken.unicodeScalars.distance(from: spoken.startIndex, to: range.lowerBound)
            let b = spoken.unicodeScalars.distance(from: spoken.startIndex, to: range.upperBound)
            let inside = cues.filter { $0.start_char >= a && $0.end_char <= b }
            rows.append(BriefingSentence(text: text, ledger_ids: ledger, chunk: 0, start_char: a, end_char: b,
                                         start: inside.first?.start ?? -1, end: inside.last?.end ?? -1, timed: !inside.isEmpty))
            cursor = range.upperBound
        }
        let names = [1: "higher", 0: "base", -1: "lower"]
        let file = String(format: "s%02d-%@-c00.m4a", segment + 1, names[level]!)
        let url = liveAudio ? tone(file, duration: t + 0.4, beeps: cues.map(\.start))?.absoluteString : nil
        let chunk = BriefingVariantChunk(url: url ?? ("https://fixture.invalid/" + file), duration: t + 0.4, text: spoken,
                                         sha256: String(repeating: String(segment + 1), count: 64), timing_status: "ready",
                                         cues: cues, speech_backend: "fixture")
        return BriefingVariant(level: level, sha256: String(format: "%064d", (segment + 1) * 10 + level + 1), text: body,
                               spoken_text: spoken, duration: chunk.duration, word_count: body.split(separator: " ").count,
                               chunks: [chunk], sentences: rows)
    }

    static var arm: String {
        ProcessInfo.processInfo.arguments.contains("--steer-after-arm") ? "after" : "during"
    }

    /// `--steer-live-audio`: real local playback, so the reader's seams can be
    /// observed in the simulator. Each variant is a tone file whose beeps sit at
    /// the fixture's word times; still invented, still nothing sent.
    static var liveAudio: Bool { ProcessInfo.processInfo.arguments.contains("--steer-live-audio") }

    private static func tone(_ name: String, duration: Double, beeps: [Double], pitch: Double = 660) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("steer-preview-" + name + ".caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let rate = 22_050.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(duration * rate)),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = buffer.frameCapacity
        let frames = Int(buffer.frameLength)
        for i in 0..<frames { samples[i] = 0 }
        for beep in beeps {
            let start = Int(beep * rate), end = min(frames, start + Int(0.2 * rate))
            guard start < end else { continue }
            for i in start..<end { samples[i] = Float(0.15 * sin(2 * Double.pi * pitch * Double(i) / rate)) }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        } catch { return nil }
        return url
    }

    static func briefing() -> MorningBriefing {
        let segments = content.enumerated().map { index, item in
            BriefingSegment(id: String(format: "s%02d", index + 1), index: index, theme: item.0, ledger_ids: item.1,
                            variants: [1, 0, -1].compactMap { level in item.2[level].map { variant(index, level: level, sentences: $0) } })
        }
        var steering = BriefingSteeringInfo()
        steering.enabled = true
        steering.arm = arm
        steering.study.study_active = true
        steering.study.study_week = arm == "after" ? 2 : 1
        steering.commands = ["higher", "lower", "again"]
        if liveAudio {
            for (cue, pitch) in [("higher", 880.0), ("lower", 440.0), ("again", 550.0), ("limit", 330.0)] {
                if let url = tone("cue-" + cue, duration: 0.5, beeps: [0.05], pitch: pitch) {
                    steering.cues[cue] = .init(url: url.absoluteString, duration: 0.5)
                }
            }
        }
        var item = MorningBriefing(id: id, day: Date.now.formatted(.iso8601.year().month().day()), title: title,
                                   text: segments.compactMap { $0.variant(0)?.text }.joined(separator: "\n\n"),
                                   status: "ready", audio_url: "https://fixture.invalid/briefing.m4a",
                                   duration: segments.compactMap { $0.variant(0)?.duration }.reduce(0, +),
                                   playlist_id: "preview-briefing-playlist")
        item.script_sha256 = String(repeating: "f", count: 64)
        item.segments = segments
        item.steering = steering
        return item
    }

    /// The mock service: the same local rule the phone uses offline.
    static func answer(_ endpoint: BriefingEndpoint, body: Data) -> BriefingPostResult {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return .rejected(Data()) }
        switch endpoint {
        case .steer:
            let b = briefing()
            guard let steering = b.steering, let command = SteerCommand(rawValue: json["command"] as? String ?? "") else {
                return .rejected(Data())
            }
            let meaning = BriefingPlanner.interpret(segments: b.segments, steering: steering, command: command,
                segmentID: json["segment_id"] as? String ?? "", sentence: json["sentence_index"] as? Int ?? 0,
                levelBefore: json["level_before"] as? Int ?? 0, phase: json["phase"] as? String ?? "during")
            struct Reply: Encodable { var ok = true; var event_id: String; var interpretation: SteerInterpretation }
            return .accepted((try? JSONEncoder().encode(Reply(event_id: json["event_id"] as? String ?? "", interpretation: meaning))) ?? Data())
        case .receipt:
            return .accepted(Data(#"{"ok":true}"#.utf8))
        case .feedback:
            return .accepted(Data(#"{"ok":true,"validation":{"path_status":"confirmed"}}"#.utf8))
        }
    }
}
#endif
