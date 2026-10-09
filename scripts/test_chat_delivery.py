#!/usr/bin/env python3
"""Run actual Swift send/stream/draft methods with inert HTTP and storage only."""
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
collaboration = (root / 'Alicia/Core/Collaboration.swift').read_text()
sheet = (root / 'Alicia/Features/Talk/ConversationSheet.swift').read_text()

def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

opening = between(store, '    func openConversation(', '    var isWalking:')
sending = between(store, '    func send(', '    /// Saved public context')
streaming = between(live, '    func stream(_ prompt: String, voice: Bool, recordingID: String, workContext: WorkDialogueContext?, surfaceContext: SurfaceContext?, requestID: String)', '    // MARK: reactions')
sheet_send = between(sheet, '    private func send()', '\n}').replace('private ', '')
models = (root / 'Alicia/Core/Models.swift').read_text().split('/// A proactive message')[0].replace('import SwiftUI', 'import Foundation')
context = between(collaboration, 'struct WorkDialogueContext:', 'enum CollaborationReturnPreferences')

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        status = {'/reject': 400, '/auth': 401, '/timeout': 408, '/server': 502}.get(self.path, 200)
        self.send_response(status)
        self.send_header('Content-Type', 'application/json' if status != 200 else 'text/event-stream')
        self.end_headers()
        if status != 200:
            self.wfile.write(json.dumps({'error': 'The prepared passage is no longer current. Refresh Together.'}).encode())
        elif self.path == '/success':
            for event in [{'reply_id': 'saved-reply'}, {'t': 'An inert answer.'}, {'done': True, 'message_id': 12}]:
                self.wfile.write(('data: ' + json.dumps(event) + '\n\n').encode())
        elif self.path == '/sse-error':
            self.wfile.write(b'data: {"error":"inert generation failure","done":true}\n\n')
        elif self.path == '/malformed':
            self.wfile.write(b'data: not-json\n\n')

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()

program = r'''
import Foundation
import CryptoKit
__MODELS__
__CONTEXT__
__FAILURE__
__DRAFTS__

struct RecordingContext {var episode_id = ""}
struct Recording {var context = RecordingContext()}
struct Archive {
 func addTranscript(_ text:String, kind:String, to id:String) {}
 func recording(_ id:String) -> Recording? {nil}
}
@MainActor final class Shared {
 var dialogueContext:WorkDialogueContext?
 var remembered:[String:WorkDialogueContext] = [:]
 func rememberDialogueContext(_ context:WorkDialogueContext, replyID:String) {remembered[replyID] = context}
}
@MainActor final class Service {
 var events:[ChatEvent] = []
 var requests:[String] = []
 var replyResult:String?
 func reply(proactiveID:String,text:String,recordingID:String,episodeID:String) async -> String? {replyResult}
 func stream(_ prompt:String,voice:Bool,recordingID:String,workContext:WorkDialogueContext?,surfaceContext:SurfaceContext?,requestID:String) -> AsyncStream<ChatEvent> {
  requests.append(requestID)
  return AsyncStream {continuation in
   for event in events {continuation.yield(event)}
   continuation.finish()
  }
 }
 func modeState() async -> (String,Int) {("",0)}
}
@MainActor final class Harness {
 let collaboration = Shared(), service = Service(), voiceArchive = Archive()
 var isStreaming = false, episodeChoiceSyncing = false, voiceReplies = false, isWalking = false
 var showConversation = false
 var composerDrafts = ComposerDrafts(directory:URL(fileURLWithPath:CommandLine.arguments[2]))
 var conversationContext = SurfaceContext(section:"studio",captured_at:"2026-10-09T17:17:00Z")
 var answeringAskID:String?
 var messages:[Message] = []
 var pendingSendRequestIDs:[String:String] = [:]
 var thinkingMode = "", walkWords = 0
 func noteContextActivity() {}
 func syncVoiceArchive() async {}
 func cancelAnswering() {answeringAskID = nil}
 func syncThoughtReturn() async {}
 func sendPrivateBody(_ text:String,recordingID:String) {}
 func surfaceContext() -> SurfaceContext {conversationContext}
 __OPEN__
 __SEND__
}
@propertyWrapper struct Stored<Value> {
 final class Box {var value:Value; init(_ value:Value) {self.value = value}}
 private let box:Box
 init(wrappedValue:Value) {box = Box(wrappedValue)}
 var wrappedValue:Value {get {box.value} nonmutating set {box.value = newValue}}
}
@MainActor struct DraftBinding {
 let drafts:ComposerDrafts
 let section:String
 var wrappedValue:String {
  get {drafts.text(for:section)}
  nonmutating set {drafts.set(newValue,for:section)}
 }
}
@MainActor struct SheetHarness {
 let store:Harness
 @Stored var sent = false
 var section:SurfaceContext {store.conversationContext}
 var privateBody:Bool {false}
 var canSend:Bool {!store.isStreaming && !store.episodeChoiceSyncing && !draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
 var draft:DraftBinding {.init(drafts:store.composerDrafts,section:section.section)}
 __SHEET_SEND__
}
struct LiveHarness {
 var base:URL
 func request(_ path:String,method:String,body:Data) -> URLRequest {
  var request = URLRequest(url:base)
  request.httpMethod = method; request.httpBody = body
  return request
 }
 func mediaURL(_ path:String) -> URL? {nil}
 __STREAM__
}
@main struct Checks {
 @MainActor static func settle(_ h:Harness) async {
  for _ in 0..<100 {
   if !h.isStreaming {return}
   await Task.yield()
   try? await Task.sleep(for:.milliseconds(2))
  }
  preconditionFailure("send did not terminate")
 }
 @MainActor static func main() async throws {
  let original = "Save this: The way to love anything is to realize that it may be lost.\n\nG. K. Chesterton"
  let target = WorkDialogueContext(goal_id:"goal",result_id:"old",section_id:"purpose",content_hash:"hash",goalTitle:"A goal",sectionTitle:"PURPOSE",quote:"Original prepared work")
  let h = Harness()
  h.collaboration.dialogueContext = target
  h.openConversation()
  precondition(h.collaboration.dialogueContext == nil && h.conversationContext.section == "studio")
  h.openConversation(workContext:target)
  precondition(h.collaboration.dialogueContext == target)
  h.openConversation()
  precondition(h.collaboration.dialogueContext == nil)

  let draftsURL = URL(fileURLWithPath:CommandLine.arguments[2])
  let drafts = ComposerDrafts(directory:draftsURL)
  h.composerDrafts = drafts
  drafts.set(original,for:"studio")
  h.service.events = [.failure(.http(400,body:Data(#"{"error":"The prepared passage is no longer current."}"#.utf8)))]
  var confirmed:Bool?
  h.send(original) {ok in confirmed = ok; if ok {drafts.acknowledge(original,for:"studio")}}
  precondition(confirmed == nil && h.isStreaming && drafts.text(for:"studio") == original)
  await settle(h)
  precondition(confirmed == false && drafts.text(for:"studio") == original)
  precondition(h.messages.last?.deliveryFailure?.definitelyRejected == true)
  precondition(h.messages.last?.text == "" && h.messages.last?.replyID == nil)
  precondition(h.pendingSendRequestIDs.isEmpty)
  precondition(ComposerDrafts(directory:draftsURL).text(for:"studio") == original)

  let rejectedID = h.service.requests.last!
  h.service.events = [.failure(.interrupted)]
  h.send(original) {confirmed = $0}
  await settle(h)
  let uncertainID = h.service.requests.last!
  precondition(confirmed == false && rejectedID != uncertainID && !h.pendingSendRequestIDs.isEmpty)
  h.service.events = [.details("saved"),.failure(.interrupted)]
  h.send(original) {ok in confirmed = ok; if ok {drafts.acknowledge(original,for:"studio")}}
  await settle(h)
  precondition(h.service.requests.last == uncertainID)
  precondition(confirmed == true && h.pendingSendRequestIDs.isEmpty && drafts.text(for:"studio").isEmpty)
  precondition(h.messages.last?.deliveryFailure == .replyInterrupted)

  h.service.events = [.token("OK"),.done(messageID:4)]
  h.send(original) {confirmed = $0}
  await settle(h)
  precondition(confirmed == true && h.messages.last?.deliveryFailure == nil && h.messages.last?.text == "OK")
  h.service.events = []
  h.send(original) {confirmed = $0}
  await settle(h)
  precondition(confirmed == false && h.messages.last?.deliveryFailure == .interrupted)
  h.service.events = [.details("")]
  h.send(original) {confirmed = $0}
  await settle(h)
  precondition(confirmed == false)

  drafts.set(original,for:"studio"); drafts.set("A Body draft",for:"body")
  drafts.acknowledge(original,for:"studio")
  precondition(drafts.text(for:"studio").isEmpty && drafts.text(for:"body") == "A Body draft")
  drafts.set("Newer words",for:"studio")
  drafts.acknowledge(original,for:"studio")
  precondition(drafts.text(for:"studio") == "Newer words")

  h.answeringAskID = "ask"
  h.send(original) {confirmed = $0}
  await settle(h)
  precondition(confirmed == false && h.messages.last?.deliveryFailure == .interrupted)
  precondition(h.answeringAskID == "ask")
  h.service.replyResult = "An inert reply to the original ask."
  h.send(original) {confirmed = $0}
  h.answeringAskID = "newer-ask"
  await settle(h)
  precondition(confirmed == true && h.answeringAskID == "newer-ask")
  h.send(original) {confirmed = $0}
  await settle(h)
  precondition(confirmed == true && h.answeringAskID == nil)
  h.answeringAskID = nil

  // Execute the real ConversationSheet.send method, including its footer and
  // draft-clear callback. The old unconditional Sent/clear fails these checks.
  let layer = SheetHarness(store:h)
  h.conversationContext = SurfaceContext(section:"studio",captured_at:"2026-10-09T17:17:00Z")
  drafts.set(original,for:"studio")
  h.service.events = [.failure(.http(400,body:Data()))]
  layer.send()
  precondition(!layer.sent && drafts.text(for:"studio") == original)
  await settle(h)
  precondition(!layer.sent && drafts.text(for:"studio") == original)
  h.service.events = [.token("An answer"),.done(messageID:15)]
  layer.send()
  precondition(!layer.sent && drafts.text(for:"studio") == original)
  // Dismiss Studio and open Body before the asynchronous send finishes.
  h.conversationContext = SurfaceContext(section:"body",captured_at:"2026-10-09T17:18:00Z")
  drafts.set("Private newer words",for:"body")
  await settle(h)
  precondition(layer.sent && drafts.text(for:"studio").isEmpty)
  precondition(drafts.text(for:"body") == "Private newer words")

  for path in ["reject","auth","timeout","server","sse-error","malformed","success"] {
   let service = LiveHarness(base:URL(string:CommandLine.arguments[1]+"/"+path)!)
   var failures:[ChatDeliveryFailure] = [], tokens:[String] = [], completed = false
   for await event in service.stream(original,voice:false,recordingID:"",workContext:target,surfaceContext:h.conversationContext,requestID:"inert") {
    switch event {
    case .failure(let failure): failures.append(failure)
    case .token(let token): tokens.append(token)
    case .done: completed = true
    case .details, .voice: break
    }
   }
   if path == "success" {precondition(failures.isEmpty && completed && tokens == ["An inert answer."])}
   else {
    precondition(failures.count == 1 && !completed && tokens.isEmpty)
    precondition(failures[0].definitelyRejected == ["reject","auth"].contains(path))
   }
  }
  print("Messaging recovery passed: explicit passage context, durable rejected drafts, safe receipt handling, and actual HTTP/SSE failure transport.")
 }
}
'''
for key, value in {
    '__MODELS__': models, '__CONTEXT__': context,
    '__FAILURE__': (root / 'Alicia/Core/ChatDelivery.swift').read_text(),
    '__DRAFTS__': (root / 'Alicia/Core/SurfaceContext.swift').read_text(),
    '__OPEN__': opening, '__SEND__': sending, '__STREAM__': streaming,
    '__SHEET_SEND__': sheet_send,
}.items():
    program = program.replace(key, value)

try:
    with tempfile.TemporaryDirectory(prefix='alicia-chat-delivery-') as directory:
        directory = Path(directory)
        source = directory / 'checks.swift'
        source.write_text(program)
        executable = directory / 'checks'
        env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(executable)], check=True, env=env)
        subprocess.run([str(executable), f'http://127.0.0.1:{server.server_port}', str(directory/'drafts')], check=True, env=env, timeout=25)
finally:
    server.shutdown()
    server.server_close()
