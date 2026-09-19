#!/usr/bin/env python3
"""Run actual context save logic and local-notification date policy without IO."""
from pathlib import Path
import os, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
models = (root / 'Alicia/Core/ContextEnrichment.swift').read_text()
view = (root / 'Alicia/Features/Talk/ContextEnrichmentView.swift').read_text()
method = view[view.index('    private func save()'):view.rfind('\n}')].replace('private func', 'func')
policy_source = (root / 'Alicia/Core/ThoughtReturnNotifier.swift').read_text()
policy = policy_source[policy_source.index('enum ThoughtReturnPolicy'):]
program = '''
import Foundation
@MainActor final class UserDefaults {
 static let standard = UserDefaults()
 var data: [String: Data] = [:]
 func set(_ value: Data?, forKey key: String) { data[key] = value }
 func removeObject(forKey key: String) { data.removeValue(forKey: key) }
}
@MainActor final class Store {
 var result: ContextChangeResult?
 var requests: [ContextChange] = []
 func changeContext(_ request: ContextChange) async -> ContextChangeResult? { requests.append(request); return result }
}
@MainActor final class Harness {
 let store = Store()
 let key = "test"
 let replyID = "reply"
 let item = ContextItem(id: "item", kind: "inferred", title: "Reading", text: "Tentative", source: "memory", as_of: "", priority: "normal", correction: "")
 var busy = false, writing = false
 var priority = "more", correction = "I want a concrete example.", status = ""
 var pending: ContextChange?
__METHOD__
}
@main struct Checks {
 @MainActor static func main() async throws {
  let h = Harness()
  await h.save()
  let request = h.pending!
  precondition(h.store.requests == [request] && !h.busy)
  let restored = Harness()
  restored.pending = try JSONDecoder().decode(ContextChange.self, from: JSONEncoder().encode(request))
  restored.correction = "Later edit"; restored.priority = "less"
  restored.store.result = ContextChangeResult(ok: true, context: nil)
  await restored.save()
  precondition(restored.pending == request && restored.store.requests == [request])
  restored.store.result = ContextChangeResult(ok: true, context: ContextEnrichment(about: [], items: [], reply_id: "", exposure: "", followups_enabled: false))
  await restored.save()
  precondition(restored.pending == nil && restored.store.requests == [request, request])
  restored.busy = true
  await restored.save()
  precondition(restored.store.requests.count == 2)
  var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
  let now = ThoughtReturnPolicy.date("2026-09-06T08:00:00Z")!
  let allowed = ThoughtReturnPolicy.date("2026-09-06T10:00:00.123Z")!
  precondition(ThoughtReturnPolicy.reservationDay(date: allowed, now: now, reserved: [], calendar: cal) == "2026-09-06")
  precondition(ThoughtReturnPolicy.reservationDay(date: allowed, now: now, reserved: ["2026-09-06"], calendar: cal) == nil)
  for raw in ["2026-09-06T07:00:00Z", "2026-09-06T19:00:00Z", "2026-09-08T10:00:00Z"] {
   precondition(ThoughtReturnPolicy.reservationDay(date: ThoughtReturnPolicy.date(raw)!, now: now, reserved: [], calendar: cal) == nil)
  }
  precondition(ThoughtReturnPolicy.date("broken") == nil)
  print("10 context checks passed: uncertain save, immutable retry, malformed success, acknowledgment, reentrancy, date parsing, daily cap, expired, quiet hours, horizon")
 }
}
'''.replace('__METHOD__', method)
with tempfile.TemporaryDirectory() as temp:
    source = Path(temp) / 'Checks.swift'; binary = Path(temp) / 'checks'
    source.write_text(models + '\n' + policy + '\n' + program)
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(binary)], env=env, check=True)
    subprocess.run([str(binary)], check=True)
