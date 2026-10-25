#!/usr/bin/env python3
"""Compile the actual client with suspended, in-memory service IO only."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Alicia/Core/LivePresence.swift').read_text()
geometry = (root / 'Alicia/DesignSystem/RelationalGeometry.swift').read_text()
stub = r'''
protocol AliciaService {
    func livePresence() async -> LivePresenceFact?
    func reportPresence(_ event: PresenceEvent) async -> Bool
}
final class MockAliciaService: AliciaService {
    func livePresence() async -> LivePresenceFact? { nil }
    func reportPresence(_ event: PresenceEvent) async -> Bool { false }
}
actor SuspendedService: AliciaService {
    var calls = 0
    var pending: [Int: CheckedContinuation<LivePresenceFact?, Never>] = [:]
    var events: [PresenceEvent] = []
    func livePresence() async -> LivePresenceFact? {
        calls += 1; let index = calls
        return await withCheckedContinuation { pending[index] = $0 }
    }
    func reportPresence(_ event: PresenceEvent) async -> Bool { events.append(event); return true }
    func release(_ index: Int, source: String) {
        var fact = LivePresenceFact(); fact.activity = "resting"; fact.source = source
        pending.removeValue(forKey: index)?.resume(returning: fact)
    }
}
@main struct Checks {
    @MainActor static func eventually(_ predicate: () async -> Bool) async {
        for _ in 0..<100 {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("inert service did not reach expected state")
    }
    @MainActor static func main() async {
        let suite = "presence-fixture-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = SuspendedService(), client = LivePresenceClient(defaults: defaults)
        client.configure(service: service, playback: { false })
        await eventually { await service.calls == 1 }
        client.setEnabled(false); client.setEnabled(true)
        await eventually { await service.calls == 2 }
        await service.release(2, source: "new-generation")
        await eventually { client.remote.source == "new-generation" }
        await service.release(1, source: "obsolete-generation")
        try? await Task.sleep(for: .milliseconds(20))
        precondition(client.remote.source == "new-generation", "cancelled read cannot overwrite a new generation")
        let first = UUID().uuidString, second = UUID().uuidString
        client.capture(session: first, active: true, level: 0.6)
        precondition(client.fact.activity == "listening" && client.fact.source == "local_capture")
        client.capture(session: second, active: true, level: 0.4)
        client.capture(session: first, active: false, level: 0)
        precondition(client.fact.activity == "listening", "old stop cannot close a new capture")
        client.capture(session: second, active: false, level: 0)
        precondition(client.fact.activity != "listening", "capture stop is immediately authoritative locally")
        await eventually { await service.events.last?.activity == "resting" }
        let events = await service.events
        precondition(zip(events, events.dropFirst()).allSatisfy { $0.sequence < $1.sequence })
        precondition(defaults.string(forKey: "alicia.livePresence.sequence") != nil, "injected defaults contain only this fixture's sequence")
        client.sceneActive(false); client.setEnabled(false)
        print("live client: cancelled reads, rapid toggles, capture ownership, authoritative stop and ordered ephemeral writer passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='presence-client-') as temp:
    source_file = Path(temp) / 'Checks.swift'
    executable = Path(temp) / 'checks'
    source_file.write_text(source + geometry + stub)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source_file), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
