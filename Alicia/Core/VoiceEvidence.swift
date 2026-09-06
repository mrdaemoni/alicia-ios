import Foundation
import AVFoundation
import CryptoKit

struct VoiceContext: Codable {
    var session_id, source, started_at, timezone: String
    var episode_id, episode_title, episode_basis, frame_id, question_presented: String
    var playback_position_ms: Int
    var local_date, local_time, weekday, activity_basis, retention: String?
    var season, previous_season, next_season: Int?
    var source_paths: [String]?
}

struct VoiceSegment: Codable, Identifiable {
    var id, sha256, started_at, ended_at: String
    var bytes: Int
    var duration, sample_rate: Double
    var channels: Int
    var uploaded: Bool?
}

struct VoiceTranscript: Codable, Identifiable {
    var id, text, kind, recorded_at: String
    var uploaded: Bool?
}

struct VoiceLink: Codable {
    var receipt_id, text, kind: String
}

struct VoiceRecording: Codable, Identifiable {
    var id: String
    var context: VoiceContext
    var segments: [VoiceSegment] = []
    var transcripts: [VoiceTranscript] = []
    var links: [VoiceLink] = []
    var deleted = false
    var contextUploaded, deletionUploaded: Bool?
    var error, correction_state: String?
    var duration: Double { segments.reduce(0) { $0 + $1.duration } }
    var orderedTranscripts: [VoiceTranscript] {
        transcripts.sorted { a, b in
            let lhs = voiceDate(a.recorded_at), rhs = voiceDate(b.recorded_at)
            return lhs == rhs ? a.id < b.id : lhs < rhs
        }
    }
    var latestWords: String {
        orderedTranscripts.last(where: { $0.kind == "correction" })?.text
            ?? orderedTranscripts.last(where: { $0.kind == "submitted" })?.text
            ?? orderedTranscripts.filter { $0.kind == "on_device" }.map(\.text).joined(separator: "\n\n")
    }
}

struct VoiceEvidencePayload: Decodable {
    struct Nearby: Decodable, Identifiable {
        var ts, role, content, receipt_id: String
        var id: String { receipt_id.isEmpty ? ts + role : receipt_id }
    }
    var recordings: [VoiceRecording]
    var nearby_messages: [Nearby]?
}

struct VoiceEvidenceResult: Decodable {
    var ok: Bool
    var deleted: Bool?
    var error, sha256: String?
    var bytes: Int?
}

func voiceDate(_ timestamp: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestamp) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: timestamp) ?? .distantPast
}

func voiceTimestamp(_ date: Date = .now) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

/// Microphone tap sink. PCM bytes are preserved independently of recognition.
/// Short finalized CAF segments bound uploads and limit damage from interruption.
final class VoiceAudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private let directory: URL
    private var file: AVAudioFile?
    private var started: Date = .now
    private var frames: AVAudioFramePosition = 0
    private var completed: [VoiceSegment] = []
    private var failure: Error?
    private var closed = false

    init(directory: URL) { self.directory = directory }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !closed, failure == nil else { return }
        do {
            if file == nil {
                let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
                started = .now
                frames = 0
                file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
            }
            try file?.write(from: buffer)
            frames += AVAudioFramePosition(buffer.frameLength)
            // <= ~4 MB at normal microphone formats. Never truncate a sample.
            let seconds = Double(frames) / buffer.format.sampleRate
            let bytes = frames * AVAudioFramePosition(buffer.format.streamDescription.pointee.mBytesPerFrame)
            if seconds >= 10 || bytes >= 3_000_000 { try finishFile() }
        } catch { failure = error }
    }

    private func finishFile() throws {
        guard file != nil else { return }
        let url = file!.url
        let rate = file!.processingFormat.sampleRate
        let channels = Int(file!.processingFormat.channelCount)
        // Closing flushes the CAF header before hashing or upload.
        file = nil
        // AVAudioFile writes are synchronous; its header length is finalized on deinit.
        let duration = Double(frames) / rate
        let bytes = try Data(contentsOf: url)
        completed.append(VoiceSegment(id: url.deletingPathExtension().lastPathComponent,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            started_at: voiceTimestamp(started), ended_at: voiceTimestamp(),
            bytes: bytes.count, duration: duration, sample_rate: rate, channels: channels, uploaded: false))
    }

    func drain(close: Bool = false) -> (segments: [VoiceSegment], error: Error?) {
        lock.lock(); defer { lock.unlock() }
        if close {
            closed = true
            do { try finishFile() } catch { failure = error }
        }
        let result = completed
        completed = []
        return (result, failure)
    }
}

/// Durable, file-backed outbox. Raw files never live in a purgeable cache.
@MainActor @Observable
final class VoiceArchive {
    private(set) var recordings: [VoiceRecording] = []
    var lastError = ""
    var syncing = false
    private var syncRequested = false
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceEvidence", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            var url = self.root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            for folder in try FileManager.default.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil) {
                let path = folder.appendingPathComponent("recording.json")
                guard FileManager.default.fileExists(atPath: path.path) else { continue }
                do {
                    var record = try JSONDecoder().decode(VoiceRecording.self, from: Data(contentsOf: path))
                    if record.deleted { try purgeFiles(record.id) }
                    else {
                        // Recover finalized or still-readable CAFs after a process interruption.
                        for audio in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
                            where audio.pathExtension == "caf" && !record.segments.contains(where: { $0.id == audio.deletingPathExtension().lastPathComponent }) {
                            do {
                                let file = try AVAudioFile(forReading: audio)
                                let data = try Data(contentsOf: audio)
                                let created = try audio.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .now
                                let duration = Double(file.length) / file.processingFormat.sampleRate
                                guard duration > 0 else { continue }
                                record.segments.append(VoiceSegment(id: audio.deletingPathExtension().lastPathComponent,
                                    sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                                    started_at: voiceTimestamp(created), ended_at: voiceTimestamp(created.addingTimeInterval(duration)),
                                    bytes: data.count, duration: duration, sample_rate: file.processingFormat.sampleRate,
                                    channels: Int(file.processingFormat.channelCount), uploaded: false))
                            } catch { record.error = "An interrupted audio file is kept but could not be opened." }
                        }
                    }
                    recordings.append(record)
                    try persist(record)
                } catch { lastError = "A recording needs recovery. Its original files have been kept." }
            }
            recordings.sort { $0.context.started_at > $1.context.started_at }
        } catch { lastError = "The recording archive could not open. Your files have not been removed." }
    }

    func directory(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func fileURL(_ recordingID: String, _ segmentID: String) -> URL {
        directory(recordingID).appendingPathComponent(segmentID + ".caf")
    }
    func recording(_ id: String) -> VoiceRecording? { recordings.first { $0.id == id } }
    func hasAudio(_ id: String) -> Bool { recording(id).map { !$0.deleted && !$0.segments.isEmpty } ?? false }

    private func persist(_ record: VoiceRecording) throws {
        try FileManager.default.createDirectory(at: directory(record.id), withIntermediateDirectories: true)
        let bytes = try JSONEncoder().encode(record)
        try bytes.write(to: directory(record.id).appendingPathComponent("recording.json"),
                        options: [.atomic, .completeFileProtection])
    }

    private func replace(_ record: VoiceRecording) throws {
        try persist(record)
        if let index = recordings.firstIndex(where: { $0.id == record.id }) { recordings[index] = record }
        else { recordings.insert(record, at: 0) }
    }

    func begin(id: String, context: VoiceContext) throws -> VoiceAudioSink {
        guard UUID(uuidString: id) != nil else { throw CocoaError(.fileWriteInvalidFileName) }
        if let old = recording(id) {
            guard !old.deleted, old.context.episode_id == context.episode_id else { throw CocoaError(.fileWriteNoPermission) }
        } else { try replace(VoiceRecording(id: id, context: context)) }
        return VoiceAudioSink(directory: directory(id))
    }

    func addSegments(_ segments: [VoiceSegment], to id: String) {
        guard var record = recording(id), !record.deleted else { return }
        for segment in segments where !record.segments.contains(where: { $0.id == segment.id }) {
            record.segments.append(segment)
        }
        record.segments.sort { $0.started_at < $1.started_at }
        do { try replace(record) }
        catch { lastError = "Audio is on this phone, but its index needs recovery. Please keep the app installed." }
    }

    @discardableResult
    func addTranscript(_ text: String, kind: String, to id: String) -> Bool {
        guard var record = recording(id), !text.isEmpty else { return false }
        record.transcripts.append(VoiceTranscript(id: UUID().uuidString, text: text, kind: kind,
                                                 recorded_at: voiceTimestamp(), uploaded: false))
        do { try replace(record); return true }
        catch { lastError = "The text version could not be saved. The original audio remains."; return false }
    }

    private func purgeFiles(_ id: String) throws {
        for file in try FileManager.default.contentsOfDirectory(at: directory(id), includingPropertiesForKeys: nil)
            where file.pathExtension == "caf" {
            try FileManager.default.removeItem(at: file)
        }
    }

    func deleteAudio(_ id: String) throws {
        guard var record = recording(id) else { return }
        record.deleted = true; record.deletionUploaded = false
        try replace(record) // tombstone persists before unlink/network
        try purgeFiles(id)
    }

    func sync(using service: AliciaService) async {
        guard !syncing else { syncRequested = true; return }
        syncing = true
        defer {
            syncing = false
            if syncRequested {
                syncRequested = false
                Task { await sync(using: service) }
            }
        }
        for id in recordings.map(\.id) {
            guard var record = recording(id) else { continue }
            if record.deleted {
                if record.deletionUploaded != true {
                    let result = await service.voiceAction(["action": "delete_audio", "recording_id": id])
                    if result?.ok == true, var current = recording(id) {
                        current.deletionUploaded = true
                        do { try purgeFiles(id); try replace(current) } catch { lastError = "Local audio deletion needs another attempt." }
                    }
                }
                // Only audio is deleted. Context and words still need to sync.
                record = recording(id) ?? record
            }
            if record.contextUploaded != true {
                guard let bytes = try? JSONEncoder().encode(record.context),
                      let context = try? JSONSerialization.jsonObject(with: bytes) else { continue }
                let result = await service.voiceAction(["action": "create", "recording_id": id, "context": context])
                if result?.deleted == true { acknowledgeDeletion(id) }
                guard result?.ok == true, var current = recording(id) else { continue }
                current.contextUploaded = true
                do { try replace(current); record = current } catch { lastError = "Recording sync needs another attempt."; continue }
            }
            for segment in record.segments where segment.uploaded != true {
                guard recording(id)?.deleted == false else { break }
                let result = await service.uploadVoice(recordingID: id, segment: segment, file: fileURL(id, segment.id))
                if result?.deleted == true { acknowledgeDeletion(id); break }
                guard result?.ok == true, result?.sha256 == segment.sha256, result?.bytes == segment.bytes,
                      var current = recording(id), !current.deleted,
                      let index = current.segments.firstIndex(where: { $0.id == segment.id }) else { break }
                current.segments[index].uploaded = true
                do { try replace(current) } catch { lastError = "Audio sync receipt could not be saved."; break }
            }
            guard let fresh = recording(id) else { continue }
            for version in fresh.transcripts where version.uploaded != true {
                let result = await service.voiceAction(["action": "transcript", "recording_id": id,
                    "event_id": version.id, "text": version.text, "kind": version.kind, "recorded_at": version.recorded_at])
                guard result?.ok == true, var current = recording(id),
                      let index = current.transcripts.firstIndex(where: { $0.id == version.id }) else { break }
                current.transcripts[index].uploaded = true
                do { try replace(current) } catch { lastError = "Text sync receipt could not be saved."; break }
            }
        }
    }

    private func acknowledgeDeletion(_ id: String) {
        guard var current = recording(id) else { return }
        current.deleted = true; current.deletionUploaded = true
        do { try replace(current); try purgeFiles(id) } catch { lastError = "Local audio deletion needs another attempt." }
    }

    func refresh(using service: AliciaService) async {
        await sync(using: service)
        guard let payload = await service.voiceRecordings(recordingID: "") else { return }
        for remote in payload.recordings {
            var merged = recording(remote.id) ?? remote
            merged.links = remote.links
            merged.correction_state = remote.correction_state
            merged.context.season = remote.context.season
            merged.context.previous_season = remote.context.previous_season
            merged.context.next_season = remote.context.next_season
            merged.context.source_paths = remote.context.source_paths
            merged.contextUploaded = true
            for segment in remote.segments {
                var received = segment; received.uploaded = true
                if let index = merged.segments.firstIndex(where: { $0.id == segment.id }) {
                    merged.segments[index] = received
                } else { merged.segments.append(received) }
            }
            for version in remote.transcripts {
                var received = version; received.uploaded = true
                if let index = merged.transcripts.firstIndex(where: { $0.id == version.id }) {
                    merged.transcripts[index] = received
                } else { merged.transcripts.append(received) }
            }
            merged.segments.sort { voiceDate($0.started_at) < voiceDate($1.started_at) }
            merged.transcripts = merged.orderedTranscripts
            if remote.deleted { merged.deleted = true; merged.deletionUploaded = true }
            do {
                try replace(merged)
                if merged.deleted { try purgeFiles(merged.id) }
            } catch { lastError = "Recording context could not refresh." }
        }
    }

    func playbackFiles(_ id: String, using service: AliciaService) async -> [URL] {
        guard let record = recording(id), !record.deleted else { return [] }
        var files: [URL] = []
        for segment in record.segments {
            guard recording(id)?.deleted == false else { return [] }
            let file = fileURL(id, segment.id)
            if !FileManager.default.fileExists(atPath: file.path) {
                guard let bytes = await service.downloadVoice(recordingID: id, segmentID: segment.id),
                      bytes.count == segment.bytes,
                      SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == segment.sha256,
                      recording(id)?.deleted == false else { lastError = "The original audio couldn't be downloaded."; return [] }
                do { try bytes.write(to: file, options: [.atomic, .completeFileProtection]) }
                catch { lastError = "The original audio couldn't be saved on this phone."; return [] }
            }
            files.append(file)
        }
        return files
    }

#if DEBUG
    static let previewID = "90100000-0000-4000-8000-000000000001"
    func seedPreview() {
        let id = Self.previewID
        let context = VoiceContext(session_id: id, source: "ios_walk", started_at: "2026-09-05T15:04:00.000Z",
            timezone: "America/Los_Angeles", episode_id: "S15E07", episode_title: "Preview · Endings Chosen",
            episode_basis: "selected", frame_id: "preview", question_presented: "Preview · Which criterion would help you decide?",
            playback_position_ms: 12345, season: 15, previous_season: 14)
        do {
            let sink = try begin(id: id, context: context)
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
            buffer.frameLength = 48000
            for index in 0..<48000 { buffer.floatChannelData![0][index] = 0 }
            sink.append(buffer)
            addSegments(sink.drain(close: true).segments, to: id)
            addTranscript("Preview recognition · I want to revisit the criteria.", kind: "on_device", to: id)
            addTranscript("Preview · I want to revisit the criteria for ending a commitment.", kind: "submitted", to: id)
        } catch { lastError = "Preview fixture could not open." }
    }
#endif
}
