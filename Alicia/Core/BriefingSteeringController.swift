import CryptoKit
import Foundation
import SwiftUI

/// The three steering endpoints share one service seam.
enum BriefingEndpoint: String { case steer, receipt, feedback }
enum BriefingPostResult {
    case accepted(Data)
    case rejected(Data)
    case unreachable
}

/// Receipts that must reach the Mac even when a run drops the connection.
///
/// Every body carries its own UUID receipt, so a retry is a no-op on the
/// server. Kept in Application Support with protection that still allows
/// writes while the phone is locked in a pocket (the audio keeps playing).
final class BriefingOutbox {
    struct Entry: Codable, Equatable { var id: String; var endpoint: String; var body: Data }
    private let url: URL
    private(set) var entries: [Entry] = []

    init(directory: URL? = nil) {
        let base = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("briefing_receipts_outbox.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(_ endpoint: BriefingEndpoint, _ body: Data, id: String) {
        guard !entries.contains(where: { $0.id == id }) else { return }
        entries.append(Entry(id: id, endpoint: endpoint.rawValue, body: body))
        save()
    }

    func remove(_ id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Verified local copies of the variant audio, so a steer switches without a
/// network wait and a run's dropouts don't stop the briefing. A copy is used
/// only when its SHA-256 matches the variant the server validated.
final class BriefingAudioCache {
    private let folder: URL
    init(directory: URL? = nil) {
        folder = (directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!)
            .appendingPathComponent("briefing-audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func file(for sha: String) -> URL? {
        guard sha.count == 64 else { return nil }
        let path = folder.appendingPathComponent(sha + ".m4a")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    func store(_ data: Data, sha: String) -> Bool {
        guard sha.count == 64, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha else { return false }
        return (try? data.write(to: folder.appendingPathComponent(sha + ".m4a"),
                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }

    /// Keep only the current briefing's audio.
    func prune(keeping shas: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where !shas.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// Steering the morning briefing while it plays (CL-20261015-steerable-briefing).
///
/// Owns the session's four-record trail: each Higher · Lower · Again press is
/// an event; the server's (or the same local rule's) reading is shown as the
/// interpretation; what actually starts playing is reported as a consequence;
/// Landed / Didn't land is bound to the heard path. A pause is only a pause:
/// nothing here reports pausing, skipping, stopping or silence as a signal.
@MainActor
@Observable
final class BriefingSteeringController {
    private(set) var briefing: MorningBriefing?
    private(set) var dial = 0
    private(set) var sessionID: String?
    private(set) var line: String?
    private(set) var ended = false
    private(set) var busy = false
    private(set) var heardPath: [BriefingPathStep] = []
    private(set) var savedVerdict: String?
    private(set) var verdictNotice = ""
    /// v1.1: headphone / lock-screen next and previous map to Higher and Lower.
    var remoteSteering: Bool {
        get { _ = remoteRevision; return UserDefaults.standard.object(forKey: Self.remoteKey) as? Bool ?? (briefing?.steering?.remote_commands_default ?? false) }
        set { UserDefaults.standard.set(newValue, forKey: Self.remoteKey); remoteRevision += 1 }
    }
    private var remoteRevision = 0
    static let remoteKey = "alicia.briefingRemoteSteering"

    @ObservationIgnored weak var reader: SpeechReader?
    @ObservationIgnored var service: AliciaService?
    @ObservationIgnored private let outbox: BriefingOutbox
    @ObservationIgnored private let cache: BriefingAudioCache
    @ObservationIgnored private var shaForURL: [String: String] = [:]
    @ObservationIgnored private var lastPiece: Int?
    @ObservationIgnored private var stretchKey: String?
    @ObservationIgnored private var pendingSeek: (index: Int, time: TimeInterval)?
    @ObservationIgnored private var sessionEnded = false
    @ObservationIgnored private var lineTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored var previewMode = false
    @ObservationIgnored var serverTimeout: Duration = .seconds(1.5)

    init(outbox: BriefingOutbox = BriefingOutbox(), cache: BriefingAudioCache = BriefingAudioCache()) {
        self.outbox = outbox
        self.cache = cache
    }

    // MARK: what views read

    var steering: BriefingSteeringInfo? { briefing?.steering }
    var arm: String { steering?.arm ?? "off" }

    func isCurrent(_ reader: SpeechReader) -> Bool {
        guard let briefing else { return false }
        return reader.current?.stableID == "morning:" + briefing.id
    }

    /// Higher · Lower · Again: during playback in a during week, only at the end in an after week.
    func controlsVisible(_ reader: SpeechReader) -> Bool {
        guard isCurrent(reader), steering?.enabled == true else { return false }
        return arm == "during" ? !ended : arm == "after" ? ended : false
    }

    /// Landed / Didn't land, identical in both arms, once the briefing ends.
    func endCheckVisible(_ reader: SpeechReader) -> Bool { isCurrent(reader) && ended && steering?.enabled == true }

    var handlesRemoteCommands: Bool {
        _ = remoteRevision
        guard let reader, remoteSteering else { return false }
        return controlsVisible(reader)
    }

    // MARK: starting

    func configure(service: AliciaService, reader: SpeechReader) {
        self.service = service
        self.reader = reader
        reader.pieceDidStart = { [weak self] index in self?.pieceStarted(index) }
        reader.playbackTick = { [weak self] index, time, delta in self?.tick(index, delta) }
        reader.didSeekPiece = { [weak self] index, time in self?.pendingSeek = (index, time) }
        reader.pathEnded = { [weak self] finished in self?.pathEnded(finished) }
        flush()
    }

    private func resolve(_ url: String) -> URL? {
        if let sha = shaForURL[url], let local = cache.file(for: sha) { return local }
        return URL(string: url)
    }

    /// Play a steerable briefing from its beginning at L0, as a new session.
    func play(_ briefing: MorningBriefing) {
        guard let reader else { return }
        endSession(reason: "replaced")
        // Stop the old path while it still belongs to the old session.
        reader.stop()
        self.briefing = briefing
        dial = 0; ended = false; heardPath = []; savedVerdict = nil; verdictNotice = ""; line = nil
        lastPiece = nil; pendingSeek = nil; stretchKey = nil
        shaForURL = [:]
        for segment in briefing.segments { for variant in segment.variants { for chunk in variant.chunks { shaForURL[chunk.url] = chunk.sha256 } } }
        let pieces = BriefingPlanner.path(briefing.segments, dial: 0, fromSegment: 0, resolve: resolve)
        guard !pieces.isEmpty else { return }
        startSession()
        reader.read(Readable(title: briefing.title, body: briefing.text, kind: "note", speechChunks: pieces,
                             speechDuration: pieces.reduce(0) { $0 + $1.duration }, stableID: "morning:" + briefing.id))
        prefetch(briefing)
    }

    private func startSession() {
        guard let briefing else { return }
        let id = UUID().uuidString
        sessionID = id; sessionEnded = false; heardPath = []
        post(.receipt, ["briefing_id": briefing.id, "receipt_id": UUID().uuidString, "session_id": id,
                        "kind": "session_started", "script_sha256": briefing.script_sha256, "arm": arm,
                        "client_ts": Self.now(), "build": AppVersion.tag])
    }

    // MARK: what actually played (record 3)

    private func pieceStarted(_ index: Int) {
        guard let reader, isCurrent(reader), reader.narrationChunks.indices.contains(index),
              let piece = reader.narrationChunks[index].piece else { return }
        defer { lastPiece = index }
        if piece.isCue { return }
        if sessionID == nil || sessionEnded { startSession() }
        var cause = piece.cause, from = piece.stretchSentence, eventID = piece.eventID
        if let seek = pendingSeek, seek.index == index {
            pendingSeek = nil
            cause = "seek"; eventID = ""
            if let variant = segment(piece.segmentID)?.variant(piece.level) {
                from = BriefingPlanner.sentence(at: seek.time, chunk: piece.chunkIndex, in: variant)
            }
        }
        let key = "\(piece.segmentID)|\(piece.level)|\(piece.variantSHA)|\(piece.stretchSentence)"
        let contiguous = lastPiece.map { $0 + 1 == index } ?? false
        // A later chunk of the stretch already sounding is not a new consequence.
        if contiguous && key == stretchKey && cause != "seek" && eventID.isEmpty { return }
        stretchKey = key
        let step = BriefingPathStep(segment_id: piece.segmentID, level: piece.level, variant_sha256: piece.variantSHA,
                                    from_sentence_index: from, seconds: 0, event_id: eventID)
        heardPath.append(step)
        guard let briefing, let sessionID else { return }
        var body: [String: Any] = ["briefing_id": briefing.id, "receipt_id": UUID().uuidString, "session_id": sessionID,
                                   "kind": "consequence", "script_sha256": briefing.script_sha256, "cause": cause,
                                   "step": Self.stepBody(step), "started_at_offset": max(0, reader.elapsed),
                                   "client_ts": Self.now()]
        if cause == "steer" || cause == "replay_at_end" { body["event_id"] = eventID }
        post(.receipt, body)
    }

    private func tick(_ index: Int, _ delta: TimeInterval) {
        guard let reader, isCurrent(reader), reader.narrationChunks.indices.contains(index),
              reader.narrationChunks[index].piece?.isCue == false, !heardPath.isEmpty else { return }
        heardPath[heardPath.count - 1].seconds += delta
    }

    private func pathEnded(_ finished: Bool) {
        if finished {
            ended = true
        } else {
            endSession(reason: "stopped")
        }
    }

    /// One session_ended per session: on stop or replace, after a verdict, or
    /// when the next session starts. Seconds heard is measured playing time.
    private func endSession(reason: String) {
        guard let briefing, let sessionID, !sessionEnded else { return }
        sessionEnded = true
        post(.receipt, ["briefing_id": briefing.id, "receipt_id": UUID().uuidString, "session_id": sessionID,
                        "kind": "session_ended", "script_sha256": briefing.script_sha256,
                        "reason": reason, "seconds_heard": heardPath.reduce(0) { $0 + $1.seconds },
                        "reached_end": ended, "heard_path": heardPath.map(Self.stepBody), "client_ts": Self.now()])
    }

    // MARK: a press (records 1 and 2)

    private func segment(_ id: String) -> BriefingSegment? { briefing?.segments.first { $0.id == id } }

    func steer(_ command: SteerCommand, input: String = "screen") {
        guard let reader, let briefing, let steering = briefing.steering, isCurrent(reader), controlsVisible(reader),
              !busy, let sessionID else { return }
        let phase = ended ? "after_end" : "during"
        let chunks = reader.narrationChunks
        // The piece being heard (a cue counts as the start of what follows it).
        guard var position = reader.currentPosition() else { return }
        if ended, let last = chunks.lastIndex(where: { $0.piece?.isCue == false }) {
            position = (last, chunks[last].clipEnd ?? chunks[last].duration + chunks[last].clipStart)
        } else if chunks[position.index].piece?.isCue == true,
                  let next = chunks.indices.first(where: { $0 > position.index && chunks[$0].piece?.isCue == false }) {
            position = (next, chunks[next].clipStart)
        }
        guard let piece = chunks[position.index].piece, !piece.isCue, let seg = segment(piece.segmentID),
              let variant = seg.variant(piece.level) else { return }
        let current = BriefingPlanner.sentence(at: position.fileTime, chunk: piece.chunkIndex, in: variant)
        var sentence = current, cut: Double? = nil
        if ended {
            sentence = variant.sentences.count - 1
        } else if command != .again {
            let point = BriefingPlanner.switchPoint(variant, chunk: piece.chunkIndex, time: position.fileTime)
            sentence = point.sentence; cut = point.cut
        }
        let eventID = UUID().uuidString
        let body: [String: Any] = ["briefing_id": briefing.id, "event_id": eventID, "session_id": sessionID,
            "segment_id": seg.id, "sentence_index": sentence, "offset_seconds": max(0, reader.elapsed),
            "command": command.rawValue, "arm": steering.arm, "client_ts": Self.now(), "level_before": piece.level,
            "phase": phase, "input": input, "script_sha256": briefing.script_sha256]
        let local = BriefingPlanner.interpret(segments: briefing.segments, steering: steering, command: command,
                                              segmentID: seg.id, sentence: sentence, levelBefore: piece.level, phase: phase)
        busy = true
        Task {
            let answer = await self.ask(body, eventID: eventID)
            self.busy = false
            var meaning: SteerInterpretation
            switch answer {
            case .server(let reading) where self.servable(reading): meaning = reading
            case .refused:
                // The Mac recorded nothing (a changed or unknown briefing): change nothing.
                self.show(steering.line("unavailable")); return
            default: meaning = local
            }
            self.show(meaning.text)
            guard !self.previewMode else { return }
            var at = (piece: position.index, current: current, sentence: sentence, cut: cut, time: position.fileTime)
            var where_ = (segment: seg, variant: variant)
            // A slow answer may arrive after the planned cut: re-plan from where
            // playback is now, with the same rule. The consequence records it.
            if !self.ended, command != .again, let now = reader.currentPosition(),
               now.index != position.index || (cut.map { now.fileTime > $0 - 0.2 } ?? false),
               let nowPiece = reader.narrationChunks[now.index].piece, !nowPiece.isCue,
               let nowSegment = self.segment(nowPiece.segmentID), let nowVariant = nowSegment.variant(nowPiece.level) {
                let point = BriefingPlanner.switchPoint(nowVariant, chunk: nowPiece.chunkIndex, time: now.fileTime)
                at = (now.index, BriefingPlanner.sentence(at: now.fileTime, chunk: nowPiece.chunkIndex, in: nowVariant),
                      point.sentence, point.cut, now.fileTime)
                where_ = (nowSegment, nowVariant)
                let replanned = BriefingPlanner.interpret(segments: briefing.segments, steering: steering, command: command,
                    segmentID: nowSegment.id, sentence: point.sentence, levelBefore: nowPiece.level, phase: phase)
                // What happens is what playback can still do; say so if it differs.
                if replanned.text != meaning.text { self.show(replanned.text) }
                meaning = replanned
            }
            self.apply(meaning, command: command, eventID: eventID, segment: where_.segment, variant: where_.variant,
                       pieceIndex: at.piece, current: at.current, sentence: at.sentence, cut: at.cut, fileTime: at.time)
        }
    }

    private enum Answer { case server(SteerInterpretation), refused, local }

    /// The server's reading; `.local` means use the identical local rule.
    private func ask(_ body: [String: Any], eventID: String) async -> Answer {
        guard let service, let data = try? JSONSerialization.data(withJSONObject: body) else { return .local }
        let call = Task { await service.morningBriefingPost(.steer, body: data) }
        let timeout = Task { try? await Task.sleep(for: serverTimeout); call.cancel() }
        let result = await call.value
        timeout.cancel()
        switch result {
        case .accepted(let response):
            struct Reply: Decodable { var interpretation: SteerInterpretation }
            return (try? JSONDecoder().decode(Reply.self, from: response)).map { .server($0.interpretation) } ?? .local
        case .rejected:
            return .refused
        case .unreachable:
            // The press still happened: deliver the same event when she's back.
            outbox.add(.steer, data, id: eventID)
            flush()
            return .local
        }
    }

    /// A server reading naming a variant this phone doesn't have yet is not usable.
    private func servable(_ meaning: SteerInterpretation) -> Bool {
        guard meaning.change == "level_changed", let effect = meaning.effective_from else { return true }
        return segment(effect.segment_id)?.variant(meaning.level_chosen) != nil
    }

    private func show(_ text: String) {
        line = text
        lineTask?.cancel()
        lineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.line = nil
        }
    }

    // MARK: the consequence of a reading

    private func apply(_ meaning: SteerInterpretation, command: SteerCommand, eventID: String, segment seg: BriefingSegment,
                       variant: BriefingVariant, pieceIndex: Int, current: Int, sentence: Int, cut: Double?,
                       fileTime: Double) {
        guard let reader, let briefing, let steering = briefing.steering else { return }
        let outcome = BriefingPlanner.consequence(meaning, segments: briefing.segments, steering: steering,
            path: reader.narrationChunks, pieceIndex: pieceIndex, current: current, sentence: sentence, cut: cut,
            fileTime: fileTime, dial: dial, ended: ended, eventID: eventID, resolve: resolve)
        dial = outcome.dial
        switch outcome.action {
        case .replaceFuture(let replacement, let tail, let immediate):
            reader.replaceFuture(after: pieceIndex, current: replacement, tail: tail, immediate: immediate)
        case .restart(let pieces):
            ended = false
            reader.restartPath(pieces)
        case .none:
            break
        }
    }

    // MARK: validation (record 4)

    func verdict(_ landed: Bool) {
        guard let briefing, let sessionID, !heardPath.isEmpty, !busy else { return }
        let body: [String: Any] = ["id": briefing.id, "event_id": UUID().uuidString, "verdict": landed ? "landed" : "didnt_land",
                                   "script_sha256": briefing.script_sha256, "session_id": sessionID,
                                   "heard_path": heardPath.map(Self.stepBody), "client_ts": Self.now()]
        busy = true
        Task {
            await self.drain()   // every consequence first, so the path can be confirmed
            let saved = await self.send(.feedback, body, id: body["event_id"] as! String)
            self.busy = false
            self.savedVerdict = landed ? "landed" : "didnt_land"
            self.verdictNotice = saved ? "Saved." : "Saved here; it will reach Alicia when she's back."
            self.endSession(reason: "finished")
        }
    }

    // MARK: delivery

    private func post(_ endpoint: BriefingEndpoint, _ body: [String: Any]) {
        guard !previewMode, let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        let id = (body["receipt_id"] ?? body["event_id"]) as? String ?? UUID().uuidString
        outbox.add(endpoint, data, id: id)
        flush()
    }

    private func send(_ endpoint: BriefingEndpoint, _ body: [String: Any], id: String) async -> Bool {
        if previewMode { return true }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        outbox.add(endpoint, data, id: id)
        await drain()
        return !outbox.entries.contains { $0.id == id }
    }

    /// Deliver queued records in order. A definite refusal is dropped (it can
    /// never succeed); an unreachable Mac keeps everything for the next try.
    func flush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            await self?.drain()
            self?.flushTask = nil
        }
    }

    private func drain() async {
        guard let service, !previewMode else { return }
        for entry in outbox.entries {
            guard let endpoint = BriefingEndpoint(rawValue: entry.endpoint) else { outbox.remove(entry.id); continue }
            switch await service.morningBriefingPost(endpoint, body: entry.body) {
            case .accepted, .rejected: outbox.remove(entry.id)
            case .unreachable: return
            }
        }
    }

    // MARK: audio

    private func prefetch(_ briefing: MorningBriefing) {
        guard !previewMode else { return }
        var wanted: [(String, String)] = []
        for segment in briefing.segments { for variant in segment.variants { for chunk in variant.chunks { wanted.append((chunk.url, chunk.sha256)) } } }
        cache.prune(keeping: Set(wanted.map(\.1)))
        Task.detached(priority: .utility) { [cache] in
            for (url, sha) in wanted where cache.file(for: sha) == nil {
                guard let remote = URL(string: url), remote.scheme?.hasPrefix("http") == true,
                      let (data, response) = try? await URLSession.shared.data(from: remote),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                _ = cache.store(data, sha: sha)
            }
        }
    }

    // MARK: helpers

    private static func stepBody(_ step: BriefingPathStep) -> [String: Any] {
        ["segment_id": step.segment_id, "level": step.level, "variant_sha256": step.variant_sha256,
         "from_sentence_index": step.from_sentence_index, "seconds": (step.seconds * 1000).rounded() / 1000,
         "event_id": step.event_id]
    }

    private static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: .now)
    }

#if DEBUG
    /// Inert fixture state: no audio, network, receipts or memory.
    func preparePreview(_ briefing: MorningBriefing, ended: Bool, line: String?) {
        previewMode = true
        self.briefing = briefing
        self.ended = ended
        self.line = line
        sessionID = "00000000-0000-4000-8000-000000000001"
        heardPath = [BriefingPathStep(segment_id: "s01", level: 0, variant_sha256: briefing.segments.first?.variant(0)?.sha256 ?? "",
                                      from_sentence_index: 0, seconds: 12)]
    }
#endif
}
