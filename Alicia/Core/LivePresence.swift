import Foundation
import Observation

struct PresenceExpression: Codable, Equatable {
    var stance = "witness"
    var source = "unavailable"
    var energy = 0.4
    var openness = 0.6
    var coherence = 0.75
}

struct LivePresenceFact: Codable, Equatable {
    var version = 1
    var activity = "unavailable"
    var source = "unavailable"
    var surface = "none"
    var level = 0.0
    var remainingMS = 0
    var deviceID: String?
    var expression = PresenceExpression()
    enum CodingKeys: String, CodingKey {
        case version, activity, source, surface, level, expression
        case remainingMS = "remaining_ms", deviceID = "device_id"
    }
    static let unavailable = LivePresenceFact()
    func fresh(after seconds: Double) -> Self {
        guard version == 1, seconds <= 3.5 else { return .unavailable }
        var value = self
        if ["listening", "thinking", "speaking"].contains(activity) && Double(remainingMS) <= seconds * 1000 {
            value.activity = "unavailable"; value.level = 0
        }
        return value
    }
}

struct PresenceEvent: Encodable {
    var device_id: String
    var session_id: String
    var sequence: Int64
    var surface = "phone"
    var activity: String
    var level: Double
    var observed_at_ms: Int64
}

enum PresencePlaybackPolicy {
    static func shared(kind: String, stableID: String?) -> Bool {
        let kinds = ["episode", "briefing", "morning_briefing", "synthesis", "thought", "dialogue"]
        return kinds.contains(kind) || (kind == "note" && stableID?.hasPrefix("morning:") == true)
    }
}

/// Live presence. Raw capture never waits for this optional channel.
@MainActor @Observable
final class LivePresenceClient {
    static let shared = LivePresenceClient()
    private(set) var enabled = false
    private(set) var remote = LivePresenceFact.unavailable
    private(set) var localCapture = false
    private(set) var localLevel = 0.0
    private(set) var localPlayback = false
    private(set) var motion = RelationalMotion(now: ProcessInfo.processInfo.systemUptime)
    private var captureID = ""
    private var service: AliciaService?
    private var playback: (() -> Bool)?
    private var playbackLevel: (() -> Double)?
    private var foreground = true
    private var loop: Task<Void, Never>?
    private var loopIdentity: UUID?
    private var writer: Task<Void, Never>?
    private var pending: PresenceEvent?
    private var receivedAt = -Double.infinity
    private var lastReport = -Double.infinity
    private let bootSession = UUID().uuidString.lowercased()
    private let device: String
    private var sequence: Int64
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let key = "alicia.livePresence.device"
        let prior = defaults.string(forKey: key)
        device = prior.flatMap(UUID.init(uuidString:))?.uuidString.lowercased() ?? UUID().uuidString.lowercased()
        defaults.set(device, forKey: key)
        sequence = max(Int64(Date.now.timeIntervalSince1970 * 1_000_000), Int64(defaults.string(forKey: "alicia.livePresence.sequence") ?? "0") ?? 0)
    }

    var fact: LivePresenceFact {
        guard enabled else { return .unavailable }
        var value = remote.fresh(after: ProcessInfo.processInfo.systemUptime - receivedAt)
        if localCapture {
            value.activity = "listening"; value.source = "local_capture"; value.surface = "phone"
            value.level = localLevel; value.remainingMS = 8000
        } else if localPlayback {
            value.activity = "speaking"; value.source = "local_playback"; value.surface = "phone"
            value.level = currentPlaybackLevel ?? 0; value.remainingMS = 8000
        } else if value.deviceID == device && ["listening", "speaking"].contains(value.activity) {
            // A delayed echo cannot reopen our own stopped capture/playback.
            value.activity = "resting"; value.level = 0; value.source = "local_stopped"
        }
        return value
    }

    var currentPlaybackLevel: Double? {
        guard !localCapture, localPlayback else { return nil }
        let value = playback?() == true ? (playbackLevel?() ?? 0) : 0
        return value.isFinite ? min(1, max(0, value)) : 0
    }

    func configure(service: AliciaService, playbackLevel: @escaping () -> Double = { 0 }, playback: @escaping () -> Bool) {
        if service is MockAliciaService {
#if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("--live-presence-preview") else { return }
#else
            return
#endif
        }
        self.service = service; self.playback = playback; self.playbackLevel = playbackLevel
        setEnabled(true)
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value { lastReport = -.infinity; startLoop() }
        else {
            loopIdentity = nil; loop?.cancel(); loop = nil
            enqueue(activity: "resting", level: 0)
            remote = .unavailable
        }
        retarget()
    }

    func sceneActive(_ value: Bool) {
        foreground = value
        if value && enabled { startLoop() }
    }

    func capture(session: String, active: Bool, level: Double) {
        if active { captureID = session }
        guard captureID == session else { return }
        let changed = localCapture != active
        localCapture = active
        localLevel = active && level.isFinite ? min(1, max(0, level)) : 0
        guard enabled else { return }
        retarget()
        let now = ProcessInfo.processInfo.systemUptime
        if changed || now-lastReport >= 1 {
            lastReport = now
            enqueue(activity: active ? "listening" : localPlayback ? "speaking" : "resting", level: localLevel)
        }
        startLoop()
    }

    private func startLoop() {
        guard loop == nil, enabled, service != nil else { return }
        let identity = UUID()
        loopIdentity = identity
        loop = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.loopIdentity == identity { self.loop = nil; self.loopIdentity = nil }
            }
            while !Task.isCancelled && self.enabled && self.loopIdentity == identity {
                let wasPlaying = self.localPlayback
                self.localPlayback = self.playback?() ?? false
                self.retarget()
                let now = ProcessInfo.processInfo.systemUptime
                if wasPlaying != self.localPlayback ||
                    ((self.localCapture || self.localPlayback) && now-self.lastReport >= 1) {
                    self.lastReport = now
                    self.enqueue(activity: self.localCapture ? "listening" : self.localPlayback ? "speaking" : "resting", level: self.localCapture ? self.localLevel : (self.currentPlaybackLevel ?? 0))
                }
                if self.foreground, let service = self.service {
                    let value = await service.livePresence()
                    guard !Task.isCancelled, self.enabled, self.loopIdentity == identity else { break }
                    self.remote = value ?? .unavailable
                    self.receivedAt = ProcessInfo.processInfo.systemUptime
                    self.retarget()
                }
                if !self.foreground && !self.localCapture && !self.localPlayback { break }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    private func enqueue(activity: String, level: Double) {
        guard service != nil else { return }
        sequence = max(sequence + 1, Int64(Date.now.timeIntervalSince1970 * 1_000_000))
        defaults.set(String(sequence), forKey: "alicia.livePresence.sequence")
        pending = PresenceEvent(device_id: device, session_id: bootSession, sequence: sequence,
                                activity: activity, level: level, observed_at_ms: Int64(Date.now.timeIntervalSince1970 * 1000))
        guard writer == nil else { return }
        writer = Task { [weak self] in
            guard let self else { return }
            defer { self.writer = nil }
            while let event = self.pending {
                self.pending = nil
                guard Date.now.timeIntervalSince1970 * 1000-Double(event.observed_at_ms) < 3000 else { continue }
                _ = await self.service?.reportPresence(event) // No retry/outbox for stale status.
            }
        }
    }
    private func retarget() {
        motion.update(fact, now: ProcessInfo.processInfo.systemUptime)
    }
}
