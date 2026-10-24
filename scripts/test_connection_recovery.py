#!/usr/bin/env python3
"""Actual Swift retry/read methods with fake HTTP, suspended IO and no app launch."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import subprocess
import tempfile
import threading

root = Path(__file__).resolve().parents[1]
store = (root / 'Alicia/Core/AppStore.swift').read_text()
live = (root / 'Alicia/Core/LiveAliciaService.swift').read_text()
service = (root / 'Alicia/Core/AliciaService.swift').read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


class Handler(BaseHTTPRequestHandler):
    counts = {}
    posts = 0

    def log_message(self, *args):
        pass

    def do_GET(self):
        authorization = self.headers.get('Authorization', '')
        lane = authorization.removeprefix('Bearer synthetic:')
        key = '/' + lane + self.path
        self.counts[key] = self.counts.get(key, 0) + 1
        status, data = 200, b'{"mode":"idle","words":0}'
        if not authorization.startswith('Bearer synthetic:') or lane == 'bad-token':
            status, data = 401, b'{"error":"unauthorized"}'
        elif lane == 'unauthorized':
            status, data = 403, b'{"error":"unauthorized"}'
        elif lane == 'fail' or (lane == 'recover' and self.counts[key] <= 3):
            status, data = 503, b'{"error":"unavailable"}'
        elif lane == 'malformed':
            data = b'not-json'
        elif lane == 'wrong-shape':
            data = b'{"error":"not a mode receipt"}'
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        type(self).posts += 1
        self.send_error(405)


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()

connection = service[service.index('enum ConnectionState'):service.index('/// The one backend-owned')]
mode = block(service, 'struct IntelligenceModeState:')
live_methods = '\n'.join(block(live, marker) for marker in (
    'private func request(', 'private func fetchOne<', 'private func retry(',
    'private struct ModeDTO:', '    func probeConnection()'))
live_methods = live_methods.replace('private ', '')
store_methods = '\n'.join(block(store, marker) for marker in (
    '    func reprobeConnection()', '    func refreshIntelligenceMode()',
    '    func setLocalIntelligence(', '    func refreshMorningBriefing()',
    '    func refreshEpisodeDay()'))
# Both real UI entry points must use the same tested recovery method.
assert 'await store.reprobeConnection()' in (root / 'Alicia/App/RootView.swift').read_text()
assert 'onRefresh: { Task { await store.reprobeConnection() } }' in (root / 'Alicia/Features/Home/EpisodeDayView.swift').read_text()

program = r'''
import Foundation
import Observation
__CONNECTION__
__MODE__
struct LiveHarness {
 let baseURL:URL, token:String
 static let readAttempts = 3
 static let retryDelays:[Duration] = [.milliseconds(1),.milliseconds(1)]
__LIVE__
}
@MainActor final class FakeService {
 var probeOK=false, holdProbe=false, holdMode=false, holdSave=false
 var probes=0, modes=0, briefings=0, episodes=0, saves=0
 var probeWait:CheckedContinuation<Bool,Never>?
 var modeWait:CheckedContinuation<IntelligenceModeState?,Never>?
 var saveWait:CheckedContinuation<IntelligenceModeState?,Never>?
 var modeValue:IntelligenceModeState?, briefingValue:String?, episodeValue:String?
 func probeConnection() async -> Bool {
  probes += 1
  if holdProbe {return await withCheckedContinuation {probeWait=$0}}
  return probeOK
 }
 func intelligenceMode() async -> IntelligenceModeState? {
  modes += 1
  if holdMode {return await withCheckedContinuation {modeWait=$0}}
  return modeValue
 }
 func setIntelligenceMode(_ mode:String) async -> IntelligenceModeState? {
  saves += 1
  if holdSave {return await withCheckedContinuation {saveWait=$0}}
  return mode == "local_first" ? .localPreview : .balanced
 }
 func morningBriefing() async -> String? {briefings += 1; return briefingValue}
 func episodeDay(day:String) async -> String? {episodes += 1; return episodeValue}
}
@MainActor final class StoreHarness {
 let service=FakeService()
 var intelligenceMode=IntelligenceModeState.balanced
 var intelligenceModeSaving=false, intelligenceModeError="Previous failure"
 var intelligenceModeRevision=0
 var connectionRecoveryTask:Task<Void,Never>?
 var morningBriefing:String?, episodeDay:String?
 var morningBriefingRefreshing=false
 let isMock=false
 var selectedSection="studio", draft="Unsent exact words", outbox=["immutable receipt"]
 func acceptEpisodeDay(_ value:String) {episodeDay=value}
 func syncThoughtReturn() async {}
__STORE__
}
@main struct Checks {
 @MainActor static func settle() async {
  for _ in 0..<20 {await Task.yield()}
  try? await Task.sleep(for:.milliseconds(5))
 }
 @MainActor static func main() async {
  let base=CommandLine.arguments[1]
  ConnectionStatus.shared.state = .unreachable
  let offline=LiveHarness(baseURL:URL(string:"http://127.0.0.1:1")!,token:"synthetic:offline")
  let reachedOffline=await offline.probeConnection();precondition(!reachedOffline)
  await settle();precondition(ConnectionStatus.shared.state == .unreachable)
  for lane in ["bad-token","unauthorized","malformed","wrong-shape","fail"] {
   ConnectionStatus.shared.state = .unreachable
   let live=LiveHarness(baseURL:URL(string:base)!,token:"synthetic:"+lane)
   let succeeded=await live.probeConnection()
   precondition(!succeeded, "Failed probe became successful")
   await settle()
   precondition(ConnectionStatus.shared.state != .ok, "Failure falsely cleared connection state")
   if lane == "unauthorized" || lane == "bad-token" {precondition(ConnectionStatus.shared.state == .unauthorized)}
  }
  let live=LiveHarness(baseURL:URL(string:base)!,token:"synthetic:recover")
  let first=await live.probeConnection();precondition(!first)
  await settle();precondition(ConnectionStatus.shared.state == .unreachable)
  let recovered=await live.probeConnection();precondition(recovered)
  await settle();precondition(ConnectionStatus.shared.state == .ok)
  print("HTTP: exhausted failure,401/403,malformed and wrong-shape200 cannot recover; subsequent valid authenticated mode does.")

  let h=StoreHarness()
  h.intelligenceMode = .localPreview;h.morningBriefing="Retained reading";h.episodeDay="Retained topic"
  await h.reprobeConnection()
  precondition(h.service.probes==1 && h.service.modes==0 && h.service.briefings==0 && h.service.episodes==0)
  precondition(h.intelligenceMode == .localPreview && h.intelligenceModeError == "Previous failure")
  precondition(h.morningBriefing == "Retained reading" && h.episodeDay == "Retained topic")

  h.service.probeOK=true;h.service.modeValue = .localPreview
  h.service.briefingValue="Recovered reading";h.service.episodeValue="Recovered topic"
  h.morningBriefingRefreshing=true // an old failing page request still owns this flag
  await h.reprobeConnection()
  precondition(h.intelligenceMode.isLocalFirst && h.intelligenceModeError.isEmpty)
  precondition(h.morningBriefing == "Recovered reading" && h.episodeDay == "Recovered topic")
  precondition(h.morningBriefingRefreshing, "Recovery must not clear another page load's busy flag")
  precondition(h.service.modes==1 && h.service.briefings==1 && h.service.episodes==1 && h.service.saves==0)
  precondition(h.selectedSection == "studio" && h.draft == "Unsent exact words" && h.outbox == ["immutable receipt"])

  h.service.modeValue=nil;h.service.briefingValue=nil;h.service.episodeValue=nil
  await h.reprobeConnection()
  precondition(h.intelligenceMode.isLocalFirst && !h.intelligenceModeError.isEmpty)
  precondition(h.morningBriefing == "Recovered reading" && h.episodeDay == "Recovered topic")
  precondition(h.connectionRecoveryTask == nil)
  print("Store: failed then recovered reads reload all three home fields; nil refreshes retain data, drafts, navigation and spending settings.")

  let c=StoreHarness();c.service.holdProbe=true
  let callers=(0..<12).map {_ in Task {await c.reprobeConnection()}}
  while c.service.probeWait == nil {await Task.yield()}
  await settle();precondition(c.service.probes==1)
  c.service.probeWait?.resume(returning:true)
  for caller in callers {await caller.value}
  precondition(c.service.modes==1 && c.service.briefings==1 && c.service.episodes==1)
  precondition(c.connectionRecoveryTask == nil)
  c.service.holdProbe=false;c.service.probeOK=true
  await c.reprobeConnection()
  precondition(c.service.probes==2 && c.service.modes==2)
  print("Concurrency:12 overlapping retries share one probe/reload; a later retry can run again.")

  let editing=StoreHarness();editing.service.probeOK=true;editing.service.holdMode=true
  let recovery=Task {await editing.reprobeConnection()}
  while editing.service.modeWait == nil {await Task.yield()}
  await editing.setLocalIntelligence(false)
  editing.service.modeWait?.resume(returning:.localPreview)
  await recovery.value
  precondition(editing.intelligenceMode == .balanced && editing.intelligenceModeError.isEmpty)
  precondition(editing.service.saves==1)

  let saving=StoreHarness();saving.service.holdSave=true;saving.service.probeOK=true
  let save=Task {await saving.setLocalIntelligence(true)}
  while saving.service.saveWait == nil {await Task.yield()}
  await saving.reprobeConnection()
  precondition(saving.intelligenceMode.isLocalFirst && saving.service.modes==0)
  saving.service.saveWait?.resume(returning:.localPreview);await save.value
  precondition(saving.intelligenceMode.isLocalFirst)
  print("Settings: recovery skips an active save; a stale read cannot overwrite a newer completed save.")

  let leaving=StoreHarness();leaving.service.probeOK=true;leaving.service.holdMode=true
  leaving.service.briefingValue="Arrived after banner cleared"
  let caller=Task {await leaving.reprobeConnection()}
  while leaving.service.modeWait == nil {await Task.yield()}
  caller.cancel() // banner can disappear as soon as the probe reports success
  leaving.service.modeWait?.resume(returning:.localPreview);await caller.value
  precondition(leaving.morningBriefing == "Arrived after banner cleared" && leaving.connectionRecoveryTask == nil)
  print("Lifecycle: removing the banner/cancelling its caller does not discard the in-flight home recovery.")
 }
}
'''.replace('__CONNECTION__', connection).replace('__MODE__', mode).replace('__LIVE__', live_methods).replace('__STORE__', store_methods)

try:
    with tempfile.TemporaryDirectory(prefix='alicia-connection-recovery-') as directory:
        directory = Path(directory)
        source, binary = directory / 'checks.swift', directory / 'checks'
        source.write_text(program)
        env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(binary)], check=True, env=env)
        subprocess.run([str(binary), f'http://127.0.0.1:{server.server_port}'], check=True, env=env, timeout=20)
        assert Handler.counts['/unauthorized/api/mode'] == 1
        assert Handler.counts['/bad-token/api/mode'] == 1
        assert Handler.counts['/malformed/api/mode'] == 1
        assert Handler.counts['/wrong-shape/api/mode'] == 1
        assert Handler.counts['/fail/api/mode'] == 3
        assert Handler.counts['/recover/api/mode'] == 4
        assert Handler.posts == 0
        print('Wiring: automatic banner and Check Again share recovery; HTTP harness issued no POSTs.')
finally:
    server.shutdown()
    server.server_close()
