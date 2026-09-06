import SwiftUI
import Observation
import AVFoundation
import MediaPlayer
import WidgetKit

@MainActor
@Observable
final class AppStore {
    // Content — starts EMPTY in live mode: sample messages are seeded only
    // in mock mode (see init), so an unreachable backend never puts words
    // in Alicia's mouth that she didn't say.
    var messages: [Message] = []
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
    /// True when the app fell back to `MockAliciaService` (no Secrets.plist
    /// / no override — see `AliciaConfig.makeService`). Sample data is a
    /// mock-mode-only affordance: it must never masquerade as her live
    /// words, and it must never reach the real home-screen widget.
    let isMock: Bool

    /// Reads any page aloud (device voice instantly, her voice when the
    /// backend has rendered it). Shares the audio session with the podcast
    /// player, so the two hand off rather than talk over each other.
    let reader = SpeechReader()
    let voiceArchive: VoiceArchive
    var walkRecordingID = UserDefaults.standard.string(forKey: "alicia.walkRecordingID") ?? "" {
        didSet { UserDefaults.standard.set(walkRecordingID, forKey: "alicia.walkRecordingID") }
    }

    init(service: AliciaService) {
        self.service = service
        self.isMock = service is MockAliciaService
        self.voiceArchive = VoiceArchive(root: service is MockAliciaService
            ? FileManager.default.temporaryDirectory.appendingPathComponent("voice-preview-" + UUID().uuidString) : nil)
        if isMock { messages = SampleData.messages }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--episode-day-preview") { messages = [] }
        if ProcessInfo.processInfo.arguments.contains("--dialogue-review-preview") {
            messages = [Message(sender: .me, text: "Preview · " + DialogueReview.preview.user_text),
                        Message(sender: .alicia, text: DialogueReview.preview.reply, replyID: DialogueReview.previewID)]
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-evidence-preview") {
            voiceArchive.seedPreview()
            messages = [Message(sender: .me, text: "Preview · I want to revisit the criteria for ending a commitment.",
                                recordingID: VoiceArchive.previewID)]
            episodeDay = EpisodeDay.preview
        }
#endif
        reader.service = service
        // Presence telemetry rides the same service (and is a no-op on the
        // mock, so previews and a missing Secrets.plist send nothing).
        PresenceTracker.shared.configure(service: service)
        // A reading and an episode are both "her, in your ears" — only one
        // of them at a time.
        reader.willStartReading = { [weak self] in self?.pauseForReading() }
        reader.episodeProgress = { [weak self] label, position, rate in
            self?.observeEpisodePlayback(label: label, position: position, rate: rate)
        }
        reader.episodeStopped = { [weak self] ended in self?.flushEpisodePlayback(ended: ended) }
        Task { await load() }
    }

    /// Step the podcast aside for a reading (paused, not forgotten — the
    /// player bar keeps its position so LISTEN picks it up again).
    private func pauseForReading() {
        guard nowPlaying != nil, isPlaying else { return }
        togglePlay()
    }

    /// Press play on anything on screen.
    func readAloud(_ item: Readable) {
        // A session that only ever reads still deserves lock-screen controls
        // — the podcast player used to be the only thing that armed them.
        configureRemoteCommandsOnce()
        if let label = item.episodeID, let track = track(forLabel: label) { chooseEpisode(track) }
        reader.read(item)
    }

    // MARK: the episode and the day
    var episodeDay: EpisodeDay?
    var episodeError = ""
    var showWalk = false
    var walkPrompt = UserDefaults.standard.string(forKey: "alicia.walkPrompt") ?? "" {
        didSet { UserDefaults.standard.set(walkPrompt, forKey: "alicia.walkPrompt") }
    }
    var walkEpisodeID = UserDefaults.standard.string(forKey: "alicia.walkEpisodeID") ?? ""
    var walkDraft = UserDefaults.standard.string(forKey: "alicia.walkDraft") ?? "" {
        didSet { UserDefaults.standard.set(walkDraft, forKey: "alicia.walkDraft") }
    }
    var walkRequestID = UserDefaults.standard.string(forKey: "alicia.walkRequestID") ?? UUID().uuidString
    var pendingWalkSave: [String: String]? = UserDefaults.standard.dictionary(forKey: "alicia.pendingWalkSave") as? [String: String] {
        didSet {
            if let pendingWalkSave { UserDefaults.standard.set(pendingWalkSave, forKey: "alicia.pendingWalkSave") }
            else { UserDefaults.standard.removeObject(forKey: "alicia.pendingWalkSave") }
        }
    }
    var isSavingWalk = false
    private var framePoll: Task<Void, Never>?
    private var playbackLabel = ""
    private var playbackPosition: Double = 0
    private var playbackClock: TimeInterval = 0
    private var playbackAccumulated: Double = 0
    private var playbackFlushing = false
    private var episodeChoiceNeedsRefresh = false
    private var playbackOutbox: [[String: Any]] =
        UserDefaults.standard.array(forKey: "alicia.playbackOutbox") as? [[String: Any]] ?? []

    private var contextActivityRevision = 0
    private var contextSettingsRevision = 0

    func noteContextActivity() {
        contextActivityRevision += 1
        ThoughtReturnNotifier.cancel()
    }

    func contextEnrichment(_ replyID: String = "") async -> ContextEnrichment? {
        await service.contextEnrichment(replyID: replyID)
    }

    func contextSource(_ replyID: String, itemID: String) async -> ContextSource? {
        await service.contextSource(replyID: replyID, itemID: itemID)
    }

    func changeContext(_ change: ContextChange) async -> ContextChangeResult? {
        noteContextActivity()
        let revision = contextActivityRevision
        if change.action == "settings" { contextSettingsRevision += 1 }
        let settingsRevision = contextSettingsRevision
        if change.action == "settings", !change.followups_enabled { ThoughtReturnNotifier.setLocalEnabled(false) }
        let result = await service.changeContext(change)
        if result?.ok == true, let fresh = result?.context {
            if change.action == "settings", settingsRevision == contextSettingsRevision {
                ThoughtReturnNotifier.setLocalEnabled(change.followups_enabled)
            }
            if revision == contextActivityRevision { await syncThoughtReturn(fresh) }
        }
        return result
    }

    private func syncThoughtReturn(_ supplied: ContextEnrichment? = nil) async {
        guard service is LiveAliciaService, !showWalk, !isWalking, !isStreaming else { return }
        let revision = contextActivityRevision
        let fresh: ContextEnrichment?
        if let supplied { fresh = supplied } else { fresh = await service.contextEnrichment(replyID: "") }
        guard revision == contextActivityRevision, let fresh else { return }
        await ThoughtReturnNotifier.sync(fresh)
    }

    func refreshEpisodeDay() async {
        if let fresh = await service.episodeDay(day: "") {
            acceptEpisodeDay(fresh)
        }
        await syncThoughtReturn()
    }

    /// One shared conversation topic, immediately visible while its receipt syncs.
    func chooseEpisode(_ track: Track) {
        guard let label = track.label, !label.isEmpty else { return }
        guard label.range(of: #"^S\d{1,2}E\d{2}$"#, options: .regularExpression) != nil else {
            episodeError = "This recording isn't available as an episode conversation yet."
            return
        }
        let chosen = EpisodeDay.choosing(.init(id: label, title: track.title, source_paths: []), previous: episodeDay)
        if episodeDay?.episode?.id == label, episodeDay?.episode_basis == "selected", episodeDay?.date == chosen.date { return }
        noteContextActivity()
        episodeDay = chosen
        playbackOutbox.append(["action": "selected", "episode_id": label,
            "event_id": UUID().uuidString, "observed_at": ISO8601DateFormatter().string(from: .now),
            "title": track.title])
        UserDefaults.standard.set(playbackOutbox, forKey: "alicia.playbackOutbox")
        Task { await flushPlaybackOutbox() }
    }

    private var pendingEpisodeChoice: [String: Any]? {
        playbackOutbox.last {
            guard $0["action"] as? String == "selected",
                  let time = $0["observed_at"] as? String,
                  let date = ISO8601DateFormatter().date(from: time) else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }

    var episodeChoiceSyncing: Bool { pendingEpisodeChoice != nil || episodeChoiceNeedsRefresh }

    func retryEpisodeSync() { Task { await flushPlaybackOutbox() } }

    private func acceptEpisodeDay(_ fresh: EpisodeDay) {
        if let pending = pendingEpisodeChoice, let label = pending["episode_id"] as? String {
            // A stale fetch/receipt cannot restore the previous topic during a switch.
            if fresh.episode?.id != label {
                episodeDay = .choosing(.init(id: label, title: pending["title"] as? String ?? label,
                                            source_paths: []), previous: episodeDay)
                return
            }
        }
        if let incoming = fresh.snapshot_revision, let current = episodeDay?.snapshot_revision,
           incoming < current { return }
        episodeDay = fresh
        episodeChoiceNeedsRefresh = false
    }

    func loadEpisodeDay(_ date: String) async -> EpisodeDay? {
        await service.episodeDay(day: date)
    }

    func awaitEpisodeFrame() {
        framePoll?.cancel()
        framePoll = Task { [weak self] in
            for _ in 0..<20 {
                guard !Task.isCancelled, let self else { return }
                await self.refreshEpisodeDay()
                if self.episodeDay?.frame_status == "ready" { return }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    @discardableResult
    func episodeAction(_ action: String, text: String = "", target: String = "",
                       verdict: String = "", episodeID: String? = nil,
                       eventID: String = UUID().uuidString) async -> Bool {
        guard let label = episodeID ?? episodeDay?.episode?.id else { return false }
        noteContextActivity()
        let result = await service.episodeAction([
            "action": action, "episode_id": label, "event_id": eventID,
            "text": text, "target_id": target, "verdict": verdict])
        guard let result, result.ok else {
            episodeError = result?.error ?? "Your change hasn't reached Alicia. Your words are still here; try again."
            return false
        }
        episodeError = ""
        if let day = result.day { acceptEpisodeDay(day) }
        awaitEpisodeFrame()
        return true
    }

    func openWalk(probe: String = "") {
        guard let episode = episodeDay?.episode else {
            episodeError = "Play an episode in Studio to begin."
            return
        }
        if let pending = pendingWalkSave, pending["episode_id"] != episode.id {
            episodeError = "A reflection for \(pending["episode_id"] ?? walkEpisodeID) still needs its save confirmed. Retry it before starting \(episode.id)."
            walkEpisodeID = pending["episode_id"] ?? walkEpisodeID
            walkRecordingID = pending["recording_id"] ?? walkRecordingID
            showWalk = true
            return
        }
        if walkEpisodeID != episode.id {
            // Keep separate drafts when a new Studio choice opens a different walk.
            var drafts = UserDefaults.standard.dictionary(forKey: "alicia.episodeWalkDrafts") as? [String: [String: String]] ?? [:]
            if (!walkDraft.isEmpty || voiceArchive.hasAudio(walkRecordingID)), !walkEpisodeID.isEmpty {
                drafts[walkEpisodeID] = ["text": walkDraft, "prompt": walkPrompt, "request_id": walkRequestID, "recording_id": walkRecordingID]
            }
            let restored = drafts.removeValue(forKey: episode.id)
            UserDefaults.standard.set(drafts, forKey: "alicia.episodeWalkDrafts")
            walkDraft = restored?["text"] ?? ""
            walkPrompt = restored?["prompt"] ?? probe
            walkRequestID = restored?["request_id"] ?? UUID().uuidString
            walkRecordingID = restored?["recording_id"] ?? walkRequestID
        } else if walkDraft.isEmpty, pendingWalkSave == nil, !voiceArchive.hasAudio(walkRecordingID) {
            walkPrompt = probe
            walkRequestID = UUID().uuidString
            walkRecordingID = walkRequestID
        }
        walkEpisodeID = episode.id
        UserDefaults.standard.set(walkEpisodeID, forKey: "alicia.walkEpisodeID")
        UserDefaults.standard.set(walkRequestID, forKey: "alicia.walkRequestID")
        episodeError = ""
        noteContextActivity()
        showWalk = true
    }

    func beginWalkRecording() async -> Bool {
        guard pendingWalkSave == nil else {
            episodeError = "Your previous save needs to finish first. Tap Retry save; the submitted words are kept here."
            return false
        }
        guard showWalk else { return false }
        prepareForRecording()
        // Capturing the original never waits for the Mac or a network request.
        // finishWalk starts/ends the shared server mode when words are submitted.
        return true
    }

    func startVoiceCapture(_ speech: SpeechTranscriber, id: String, walk: Bool) throws {
        guard !isMock else { throw CocoaError(.featureUnsupported) }
        let episodeID = walk ? walkEpisodeID : episodeDay?.episode?.id ?? ""
        let sameEpisode = episodeDay?.episode?.id == episodeID
        let context = VoiceContext(session_id: id, source: walk ? "ios_walk" : "ios_dialogue",
            started_at: voiceTimestamp(), timezone: TimeZone.current.identifier,
            episode_id: episodeID, episode_title: sameEpisode ? episodeDay?.episode?.title ?? "" : episodeID,
            episode_basis: sameEpisode ? episodeDay?.episode_basis ?? "" : "",
            frame_id: sameEpisode ? episodeDay?.frame_id ?? "" : "", question_presented: walk ? walkPrompt : "",
            playback_position_ms: sameEpisode ? episodeDay?.position_ms ?? 0 : 0)
        let sink = try voiceArchive.begin(id: id, context: context)
        try speech.start(sink: sink, onSegments: { [weak self] segments in
            guard let self else { return }
            self.voiceArchive.addSegments(segments, to: id)
            Task { await self.syncVoiceArchive() }
        }, onTranscript: { [weak self] text in
            guard let self else { return }
            self.voiceArchive.addTranscript(text, kind: "on_device", to: id)
            Task { await self.syncVoiceArchive() }
        })
        Task { await syncVoiceArchive() }
    }

    func syncVoiceArchive() async { if !isMock { await voiceArchive.sync(using: service) } }
    func refreshVoiceArchive() async { if !isMock { await voiceArchive.refresh(using: service) } }
    func voiceDetail(_ id: String) async -> VoiceEvidencePayload? { await service.voiceRecordings(recordingID: id) }
    func playOriginalVoice(_ id: String) async -> [URL] {
        prepareForRecording()
        return await voiceArchive.playbackFiles(id, using: service)
    }
    func correctVoice(_ id: String, text: String) async -> Bool {
        guard voiceArchive.addTranscript(text, kind: "correction", to: id) else { return false }
        await syncVoiceArchive()
        await refreshEpisodeDay()
        return true
    }
    func deleteOriginalVoice(_ id: String) async {
        do { try voiceArchive.deleteAudio(id); await syncVoiceArchive() }
        catch { voiceArchive.lastError = "Audio deletion needs another attempt." }
    }

    func pauseEpisodeWalk() {
        Task {
            if isWalking {
                _ = await service.modeAction("end_walk", topic: "")
                thinkingMode = "idle"
            }
        }
    }

    func prepareForRecording() {
        if isPlaying { togglePlay() }
        reader.stop()
        voicePlayer?.pause()
    }

    func finishEpisodeWalk() async -> Bool {
        if walkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           voiceArchive.hasAudio(walkRecordingID), pendingWalkSave == nil {
            // Audio-only is a valid saved source, not fabricated transcript text.
            showWalk = false
            pauseEpisodeWalk()
            walkRecordingID = ""
            walkRequestID = UUID().uuidString
            UserDefaults.standard.set(walkRequestID, forKey: "alicia.walkRequestID")
            await syncVoiceArchive()
            return true
        }
        let pending = pendingWalkSave ?? ["text": walkDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                                          "episode_id": walkEpisodeID, "request_id": walkRequestID, "prompt": walkPrompt,
                                          "recording_id": walkRecordingID]
        let text = pending["text"] ?? ""
        guard !text.isEmpty, !isSavingWalk else { return false }
        guard text.unicodeScalars.count <= 60000 else {
            pendingWalkSave = nil
            episodeError = "Please save this reflection in smaller parts. Your words are still here to edit."
            return false
        }
        pendingWalkSave = pending
        isSavingWalk = true
        defer { isSavingWalk = false }
        guard let receipt = await service.finishWalk(text: text, episodeID: pending["episode_id"] ?? walkEpisodeID,
                                                      requestID: pending["request_id"] ?? walkRequestID, prompt: pending["prompt"] ?? "",
                                                      recordingID: pending["recording_id"] ?? "") else {
            episodeError = "I couldn't confirm the save. The submitted words are kept here; tap Retry save."
            return false
        }
        guard receipt.ok else {
            // Definite rejections remain editable. Only an uncertain result
            // keeps the exact pending submission locked for retry.
            pendingWalkSave = nil
            walkRequestID = UUID().uuidString
            UserDefaults.standard.set(walkRequestID, forKey: "alicia.walkRequestID")
            episodeError = receipt.message ?? "The reflection wasn't accepted. Your words are still here to edit."
            return false
        }
        pendingWalkSave = nil
        let recordedID = pending["recording_id"] ?? walkRecordingID
        if voiceArchive.recording(recordedID) != nil {
            voiceArchive.addTranscript(text, kind: "submitted", to: recordedID)
            Task { await syncVoiceArchive() }
        }
        messages.append(Message(sender: .me, text: text, recordingID: recordedID.isEmpty ? nil : recordedID))
        // Never erase words that arrived after the submitted snapshot.
        if walkDraft.trimmingCharacters(in: .whitespacesAndNewlines) == text { walkDraft = "" }
        walkRequestID = UUID().uuidString
        walkRecordingID = ""
        UserDefaults.standard.set(walkRequestID, forKey: "alicia.walkRequestID")
        thinkingMode = "idle"
        episodeError = ""
        showWalk = false
        selectedSection = .mind
        await refreshEpisodeDay()
        awaitEpisodeFrame()
        return true
    }

    /// Positive, continuous AVPlayer progress; seeks/stalls/paused time do not count.
    func observeEpisodePlayback(label: String, position: Double, rate: Double = 1) {
        guard !label.isEmpty, position.isFinite else { return }
        let clock = ProcessInfo.processInfo.systemUptime
        if playbackLabel != label || playbackClock == 0 {
            playbackLabel = label
            playbackPosition = position
            playbackClock = clock
            playbackAccumulated = 0
            enqueuePlayback("playing", label: label, position: position)
            return
        }
        let elapsed = clock - playbackClock
        let advanced = position - playbackPosition
        playbackClock = clock
        playbackPosition = position
        if elapsed > 0, elapsed < 3, advanced > 0, advanced <= elapsed * max(1, rate) + 1 {
            playbackAccumulated += elapsed
        }
        if playbackAccumulated >= 15 {
            enqueuePlayback("progress", label: label, position: position,
                            played: playbackAccumulated)
            playbackAccumulated = 0
        }
    }

    func flushEpisodePlayback(ended: Bool = false) {
        guard !playbackLabel.isEmpty else { return }
        if playbackAccumulated > 0 || ended {
            enqueuePlayback(ended ? "finished" : "progress", label: playbackLabel,
                            position: playbackPosition, played: playbackAccumulated)
        }
        playbackAccumulated = 0
        playbackClock = 0
    }

    private func enqueuePlayback(_ action: String, label: String, position: Double, played: Double = 0) {
        playbackOutbox.append(["action": action, "episode_id": label,
                               "position_ms": Int(position * 1000), "played_ms": Int(played * 1000),
                               "event_id": UUID().uuidString, "observed_at": ISO8601DateFormatter().string(from: .now)])
        UserDefaults.standard.set(playbackOutbox, forKey: "alicia.playbackOutbox")
        Task { await flushPlaybackOutbox() }
    }

    private func flushPlaybackOutbox() async {
        guard !playbackFlushing else { return }
        playbackFlushing = true
        defer { playbackFlushing = false }
        while let first = playbackOutbox.first {
            guard let receipt = await service.episodeAction(first) else {
                episodeError = "The episode hasn't synced to Alicia yet. Your choice and listening are kept here for retry."
                return
            }
            if !receipt.ok {
                guard receipt.retryable == false else {
                    episodeError = receipt.error ?? "The episode hasn't synced. I'll retry when connected."
                    return
                }
                // Keep a rejected receipt locally for inspection, but let a new
                // valid choice proceed. Uncertain deliveries stay in the outbox.
                var rejected = UserDefaults.standard.array(forKey: "alicia.rejectedEpisodeReceipts") as? [[String: Any]] ?? []
                rejected.append(first.merging(["error": receipt.error ?? "Rejected"]) { _, new in new })
                UserDefaults.standard.set(rejected, forKey: "alicia.rejectedEpisodeReceipts")
                playbackOutbox.removeFirst()
                UserDefaults.standard.set(playbackOutbox, forKey: "alicia.playbackOutbox")
                episodeError = receipt.error ?? "That episode is unavailable. Choose another in Studio."
                if first["action"] as? String == "selected", pendingEpisodeChoice == nil {
                    episodeDay = nil
                    episodeChoiceNeedsRefresh = true
                }
                if let fresh = await service.episodeDay(day: "") { acceptEpisodeDay(fresh) }
                continue
            }
            playbackOutbox.removeFirst()
            UserDefaults.standard.set(playbackOutbox, forKey: "alicia.playbackOutbox")
            if ["selected", "playing"].contains(first["action"] as? String ?? "") {
                if let day = receipt.day { acceptEpisodeDay(day) }
                episodeError = ""
                awaitEpisodeFrame()
            }
        }
        if episodeChoiceNeedsRefresh { await refreshEpisodeDay() }
    }

    // MARK: playlists — the listening queues (Studio)

    /// Her weekly mind note. Empty string means she had nothing citable this
    /// week — the view renders nothing, never a placeholder.
    var mindNote: String = ""

    var playlists: [Playlist] = []

    func loadPlaylists() async {
        playlists = await service.playlists()
    }

    /// Play a whole queue from a position. This is the driving/walking path:
    /// press once, then the phone goes in a pocket.
    func playPlaylist(_ playlist: Playlist, from index: Int = 0) {
        configureRemoteCommandsOnce()
        if playlist.readables.indices.contains(index),
           let label = playlist.readables[index].episodeID,
           let track = track(forLabel: label) { chooseEpisode(track) }
        reader.play(queue: playlist.readables, from: index,
                    playlist: playlist.name)
    }

    /// Every mutation goes through here: the backend returns the whole
    /// refreshed shelf, so there is no local copy to drift.
    @discardableResult
    private func playlistAction(_ action: String,
                                _ body: [String: Any]) async -> Bool {
        guard let updated = await service.playlistAction(action, body: body) else {
            return false
        }
        playlists = updated
        return true
    }

    func createPlaylist(named name: String) async {
        await playlistAction("create", ["name": name])
    }

    func renamePlaylist(_ id: String, to name: String) async {
        await playlistAction("rename", ["playlist_id": id, "name": name])
    }

    func deletePlaylist(_ id: String) async {
        await playlistAction("delete", ["playlist_id": id])
    }

    func addToPlaylist(_ id: String, synthesis: FeaturedSynthesis) async {
        await playlistAction("add", [
            "playlist_id": id, "id": synthesis.pinID, "kind": "synthesis",
            "title": synthesis.title, "body": synthesis.body,
            "source": synthesis.date,
        ])
    }

    /// Queue a podcast episode. Unlike a synthesis this needs no voicing —
    /// the wav already exists, so it carries its own URL and plays at once.
    func addEpisodeToPlaylist(_ id: String, track: Track) async {
        await playlistAction("add", [
            "playlist_id": id, "id": track.playlistItemID, "kind": "episode",
            "title": track.title, "source": track.label ?? "",
            "duration": track.duration,
            "audio_url": track.fileName ?? "",
        ])
    }

    func removeFromPlaylist(_ id: String, itemID: String) async {
        await playlistAction("remove", ["playlist_id": id, "id": itemID])
    }

    func reorderPlaylist(_ id: String, order: [String]) async {
        await playlistAction("reorder", ["playlist_id": id, "order": order])
    }

    /// Which playlists already hold this piece — drives the picker's ticks.
    func playlistsHolding(_ itemID: String) -> Set<String> {
        Set(playlists.filter { p in p.items.contains { $0.id == itemID } }
                     .map(\.id))
    }

    /// True once the sample seed has been replaced by her real proactive
    /// feed — never clobber a conversation in progress on refresh.
    private var liveTimelineSeeded = false

    func load() async {
        Task { await refreshVoiceArchive() }
        let messagesAtStart = messages.map(\.id)
        async let day = service.episodeDay(day: "")
        async let history = service.conversationHistory()
        async let t = service.thoughts()
        async let tr = service.tracks()
        async let g = service.gallery()
        async let h = service.health()
        // v29: 6 starved the Dialogue — the backend sends ~9/day and the
        // feed is capped at 100 server-side; 30 gives real history.
        async let p = service.proactive(limit: 30)
        async let m = service.modeState()
        async let sy = service.syntheses()
        async let hc = service.homeContext()
        async let pls = service.playlists()
        if let fresh = await day { acceptEpisodeDay(fresh) }
        if let transcript = await history, !isStreaming, messages.map(\.id) == messagesAtStart {
            messages = transcript.messages.map { row in
                Message(sender: row.role == "user" ? .me : .alicia, text: row.content,
                        date: Self.historyDate(row.ts), replyID: row.reply_id, recordingID: row.recording_id)
            }
        }
        Task { await flushPlaybackOutbox() }
        // Keep-last-known: nil means the fetch FAILED (network/auth/decode)
        // — never wipe a populated tab over one bad refresh. A non-nil
        // empty array is a real "backend has nothing" and does overwrite.
        // Empty is a real answer here (nothing citable this week), so it
        // overwrites — unlike the keep-last-known arrays below.
        if let fresh = await t { thoughts = fresh }
        if let fresh = await tr { tracks = fresh }
        if let fresh = await g { gallery = fresh }
        if let fresh = await h { health = fresh }
        let freshHome = await hc
        if let freshHome { homeContext = freshHome }
        // Keep-last-known, same rule: a failed orbit fetch must not empty
        // the Us tab (v30).
        (thinkingMode, walkWords) = await m
        let shelf = await sy
        if !shelf.isEmpty { syntheses = shelf }
        // Same keep-last-known rule: a failed fetch must not empty Studio's
        // shelf of queues he built.
        let queues = await pls
        if !queues.isEmpty { playlists = queues }
        if thinkerNetwork == nil {
            thinkerNetwork = await service.thinkers()
        }
        publishWidgetCache(hasFreshData: episodeDay != nil)
        Task { await refreshEpisodeThinkers() }
        let pro = await p
        if !pro.isEmpty {
            proactiveFeed = pro
            ProactiveNotifier.markSeen(pro)

        }
    }

    private static func historyDate(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? .distantPast
    }

    // MARK: home-screen widget
    /// The widget reads a shared app-group cache — no network of its own.
    /// Refresh it (and the timelines) whenever the app loads fresh data.
    /// `hasFreshData` stamps `widget.cachedAt` only when this load actually
    /// got live content, so the widget can dim week-old words instead of
    /// presenting them as today's.
    private func publishWidgetCache(hasFreshData: Bool) {
        // Mock mode must never write sample content into the REAL
        // home-screen widget of a live install.
        guard !isMock else { return }
        guard let shared = UserDefaults(suiteName: "group.com.myalicia.app") else { return }
        if let day = episodeDay, let episode = day.episode {
            shared.set("With you today", forKey: "widget.greeting")
            shared.set(episode.title.strippedEmojis, forKey: "widget.featuredTitle")
            shared.set(day.focus.strippedEmojis, forKey: "widget.note")
            shared.set("", forKey: "widget.quote")
            shared.set(episode.id, forKey: "widget.todayLabel")
            shared.set(episode.title.strippedEmojis, forKey: "widget.todayTitle")
            shared.set(day.focus.strippedEmojis, forKey: "widget.context")
            shared.set(day.probes.first?.question.strippedEmojis ?? "What stayed with you?", forKey: "widget.carry")
        } else {
            for key in ["greeting", "featuredTitle", "note", "quote", "todayLabel", "todayTitle", "context", "carry"] {
                shared.removeObject(forKey: "widget." + key)
            }
        }
        if hasFreshData {
            shared.set(Date().timeIntervalSince1970, forKey: "widget.cachedAt")
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
        await refreshEpisodeDay()
        await flushPlaybackOutbox()
        let fresh = await service.proactive(limit: 30)
        guard !fresh.isEmpty else { return }
        let known = Set(proactiveFeed.map(\.id))
        let new = fresh.filter { !known.contains($0.id) }
        proactiveFeed = fresh
        guard !new.isEmpty else { return }
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
    /// A thinker sheet presented IN PLACE (v27) — tapping a thinker on the
    /// home screen opens them right there instead of yanking to Knowledge.
    var presentThinker: Thinker?

    /// Resolve + present a thinker wherever you are. v29: NEVER a dead
    /// end — exact match, then folded (case/diacritic-blind) match, then a
    /// synthesized sheet (portrait + wiki extract + share still work) for
    /// episode thinkers who aren't in the curated network yet (Bhagavad
    /// Gita, Dogen, Shinran... — 17 such names in current shownotes).
    func showThinker(named name: String) {
        let all = thinkerNetwork?.thinkers ?? []
        if let t = all.first(where: { $0.name == name }) {
            presentThinker = t
            return
        }
        let folded = name.inkFolded
        if let t = all.first(where: { $0.name.inkFolded == folded }) {
            presentThinker = t
            return
        }
        presentThinker = Thinker(
            name: name, anchor: false,
            tagline: "from today's episode — not yet in the master map",
            themes: [], works: "", relation: "", related: nil)
    }
    /// Which room the Knowledge tab shows: 0 = the shelf, 1 = the thinkers.
    var knowledgeSegment = 0
    /// The whole arc since her birth (fetched when the sheet opens).
    var timeline: [TimelineDay] = []

    // MARK: the loops (Us tab home context)
    /// Season arc → episode trail → today's episode → knowledge cards.
    var homeContext: HomeContext?
    /// The live orbit of what we actually talk about (`/api/context`).
    var sharedContext: SharedContext?
    /// Her morning/evening self-reflections (`/api/reflections`).
    var reflections: [Reflection] = []

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

    // MARK: pins (v26)
    /// Held items live in homeContext.pinned (backend-persisted); this
    /// mirrors ids for O(1) mark rendering.
    var pinnedIDs: Set<String> {
        Set((homeContext?.pinned ?? []).map(\.id))
    }

    func isPinned(_ id: String) -> Bool { pinnedIDs.contains(id) }

    /// Toggle a pin — optimistic locally, persisted by the backend, and
    /// (on pin) recorded as interest in her model of Hector.
    func togglePin(id: String, kind: String, title: String,
                   body: String = "", thinker: String = "",
                   source: String = "") {
        let pinning = !isPinned(id)
        let card = HomeContext.Card(
            id: id, kind: kind, title: title, body: body, thinker: thinker,
            tagline: "", themes: [], source: source, badge: "held")
        if homeContext == nil {
            homeContext = HomeContext(season: nil, trail: [], today: nil,
                                      cards: [], pinned: [], contextLine: "")
        }
        if pinning {
            homeContext?.pinned.removeAll { $0.id == id }
            homeContext?.pinned.insert(card, at: 0)
        } else {
            homeContext?.pinned.removeAll { $0.id == id }
        }
        Task {
            _ = await service.pin(action: pinning ? "pin" : "unpin",
                                  id: id, kind: kind, title: title,
                                  body: body, thinker: thinker, source: source)
        }
    }

    func togglePin(card: HomeContext.Card) {
        togglePin(id: card.id, kind: card.kind, title: card.title,
                  body: card.body, thinker: card.thinker, source: card.source)
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

    /// True from the moment a reply is asked for until the stream ends.
    /// Dialogue's presence reads this to show her *thinking* — the one place
    /// in the app where "she is working right now" is literally true.
    private(set) var isStreaming = false
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

    // MARK: answering her asks (v23)
    /// When set, the Dialogue composer is answering one of her explicit
    /// asks: the next send routes through /api/reply with this proactive
    /// id — landing as Tier-3 capture + circulation attribution, exactly
    /// like answering her on Telegram — instead of opening a fresh chat
    /// turn.
    var answeringAskID: String?
    var answeringAskExcerpt: String = ""

    func beginAnswering(_ message: Message) {
        guard let pid = message.proactiveID else { return }
        answeringAskID = pid
        answeringAskExcerpt = String(
            message.text.strippedLeadingEmoji.prefix(70))
    }

    func cancelAnswering() {
        answeringAskID = nil
        answeringAskExcerpt = ""
    }

    func send(_ text: String, recordingID: String = "") {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isStreaming, !episodeChoiceSyncing else { return }
        noteContextActivity()
        if !recordingID.isEmpty {
            voiceArchive.addTranscript(clean, kind: "submitted", to: recordingID)
            Task { await syncVoiceArchive() }
        }
        if let askID = answeringAskID {
            let episodeID = voiceArchive.recording(recordingID)?.context.episode_id ?? ""
            cancelAnswering()
            messages.append(Message(sender: .me, text: clean, recordingID: recordingID.isEmpty ? nil : recordingID))
            Task {
                let reply = await service.reply(proactiveID: askID, text: clean, recordingID: recordingID, episodeID: episodeID)
                if let reply, !reply.isEmpty {
                    messages.append(Message(sender: .alicia, text: reply))
                } else {
                    messages.append(Message(
                        sender: .alicia,
                        text: "(couldn't reach her — your answer didn't land; try again)"))
                }
            }
            return
        }
        messages.append(Message(sender: .me, text: clean, recordingID: recordingID.isEmpty ? nil : recordingID))
        let idx = messages.count
        messages.append(Message(sender: .alicia, text: ""))
        isStreaming = true
        Task {
            do {
                // `defer` rather than a trailing assignment: a thrown or cancelled
                // stream must not leave her looking permanently mid-thought.
                defer { isStreaming = false }
                for await event in service.stream(clean, voice: voiceReplies, recordingID: recordingID) {
                    guard messages.indices.contains(idx) else { break }
                    switch event {
                    case .token(let t):   messages[idx].text += t
                    case .details(let id): messages[idx].replyID = id
                    case .voice(let url): messages[idx].voiceURL = url
                    case .done(let mid):  messages[idx].messageID = mid
                    }
                }
                // During a walk the backend accumulates instead of chatting —
                // keep the word counter fresh.
                if isWalking { (thinkingMode, walkWords) = await service.modeState() }
            }
            await syncThoughtReturn()
        }
    }

    /// Saved public context for one particular reply.
    func replyInspection(_ replyID: String) async -> DialogueReview? {
        await service.dialogueReview(replyID: replyID)
    }

    func saveReplyReview(_ mutation: DialogueMutation) async -> DialogueMutationResult? {
        await service.dialogueReviewAction(mutation)
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

    func play(_ track: Track, chooseTopic: Bool = true) {
        if chooseTopic { chooseEpisode(track) }
        // An episode starting ends a reading outright — unlike the reverse,
        // there's no position worth keeping once you've chosen the podcast.
        reader.stop()
        // Re-tapping the current track (e.g. opening its detail page)
        // must not restart it from zero.
        if nowPlaying?.id == track.id, player != nil {
            if !isPlaying { isPlaying = true; player?.play() }
            return
        }
        flushEpisodePlayback()
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
        if !isPlaying, let track = nowPlaying { chooseEpisode(track) }
        if isPlaying { flushEpisodePlayback() }
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
        flushEpisodePlayback()
        defer { isScrubbing = false }
        guard let player, let d = nowPlaying?.duration, d > 0 else { return }
        let target = progress * d
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        updateNowPlayingElapsed(target)
    }

    /// Jump ±15s (player bar's back/forward).
    func skip(_ delta: Double) {
        flushEpisodePlayback()
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
                if p.timeControlStatus == .playing, let label = self.nowPlaying?.label {
                    self.observeEpisodePlayback(label: label, position: time.seconds, rate: Double(self.playbackRate))
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushEpisodePlayback(ended: true)
                self?.next(chooseTopic: false)
            }
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
        // A reading and an episode never run at once, so whichever is live
        // owns the lock screen. The reader is checked first: it's the one
        // that just took the audio session.
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.reader.isActive {
                    if !self.reader.isSpeaking { self.reader.toggle() }
                    return
                }
                guard self.nowPlaying != nil else { return }
                if !self.isPlaying { self.togglePlay() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.reader.isActive {
                    if self.reader.isSpeaking { self.reader.toggle() }
                    return
                }
                guard self.nowPlaying != nil else { return }
                if self.isPlaying { self.togglePlay() }
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.reader.isActive else { self.next(); return }
                // In a playlist these are real track buttons — the steering
                // wheel controls have to move between pieces. Reading one
                // piece alone, there is nowhere to skip to but forward.
                self.reader.hasNext ? self.reader.next() : self.reader.skip(15)
            }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.reader.isActive else { self.previous(); return }
                self.reader.queueItems.count > 1
                    ? self.reader.previous() : self.reader.skip(-15)
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            MainActor.assumeIsolated {
                guard let self,
                      let e = event as? MPChangePlaybackPositionCommandEvent
                else { return }
                if self.reader.isActive {
                    let d = self.reader.duration
                    guard d > 0 else { return }
                    self.reader.scrub(to: e.positionTime / d)
                    self.reader.commitScrub()
                    return
                }
                guard let p = self.player else { return }
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

    func next(chooseTopic: Bool = true) {
        guard let current = nowPlaying,
              let i = tracks.firstIndex(of: current) else { return }
        play(tracks[(i + 1) % tracks.count], chooseTopic: chooseTopic)
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
                if self.progress >= 1 { self.next(chooseTopic: false) }
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
