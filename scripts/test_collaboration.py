#!/usr/bin/env python3
"""Actual collaboration models/outbox/notifier methods with isolated defaults and fake IO."""
from pathlib import Path
import os, subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
models=(root/'Alicia/Core/Collaboration.swift').read_text()
notifier=(root/'Alicia/Core/CollaborationNotifier.swift').read_text().replace('import UserNotifications','')
policy=(root/'Alicia/Core/ThoughtReturnNotifier.swift').read_text().split('enum ThoughtReturnPolicy')[1]
program=r'''
import Foundation
struct ContextSource:Codable {var title,text,notice:String}
protocol AliciaService {
 func collaboration() async -> CollaborationState?
 func collaborationAction(_ request:CollaborationMutation) async -> CollaborationResponse?
 func collaborationSource(connectionID:String,resultID:String,evidenceID:String) async -> ContextSource?
}
@MainActor enum ThoughtReturnNotifier {static func cancel(){}}
struct UNNotificationSettings {enum AuthorizationStatus{case authorized,provisional,denied};var authorizationStatus:AuthorizationStatus}
class UNMutableNotificationContent {var title="",body="";enum Sound{case `default`};var sound:Sound?;var userInfo:[String:String]=[:]}
struct UNCalendarNotificationTrigger {var dateMatching:DateComponents;var repeats:Bool}
struct UNNotificationRequest {var identifier:String;var content:UNMutableNotificationContent;var trigger:UNCalendarNotificationTrigger}
@MainActor class UNUserNotificationCenter {
 static let shared=UNUserNotificationCenter();static func current()->UNUserNotificationCenter{shared}
 var requests:[UNNotificationRequest]=[];var removed:[String]=[]
 var suspend=false;var waiter:CheckedContinuation<UNNotificationSettings,Never>?
 func notificationSettings() async -> UNNotificationSettings {if suspend{return await withCheckedContinuation{waiter=$0}};return .init(authorizationStatus:.authorized)}
 func add(_ request:UNNotificationRequest) async throws {requests.append(request)}
 func removePendingNotificationRequests(withIdentifiers ids:[String]) {removed += ids}
}
@MainActor final class Fake:AliciaService {
 var value:CollaborationState?,result:CollaborationResponse?
 var requests:[CollaborationMutation]=[]
 var suspend=false;var waiter:CheckedContinuation<CollaborationResponse?,Never>?
 func collaboration() async -> CollaborationState? {value}
 func collaborationSource(connectionID:String,resultID:String,evidenceID:String) async -> ContextSource?{nil}
 func collaborationAction(_ request:CollaborationMutation) async -> CollaborationResponse? {
  requests.append(request);if suspend{suspend=false;return await withCheckedContinuation{waiter=$0}};return result
 }
}
@main struct Checks {
 @MainActor static func main() async throws {
  if CommandLine.arguments.count > 1 {
   let bytes = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
   let actual = try JSONDecoder().decode(CollaborationState.self,from:bytes)
   precondition(!actual.goals.isEmpty && !actual.connections.isEmpty && !actual.agreements.isEmpty)
   print("Actual backend fixture decoded: goals, connections, agreements, signals, followup")
  }
  let suite="collaboration-check-"+UUID().uuidString
  let defaults=UserDefaults(suiteName:suite)!
  defer {defaults.removePersistentDomain(forName:suite)}
  func state(_ revision:Int)->CollaborationState { .init(revision:revision,goals:[],connections:[],agreements:[],results:[],signals:[],pending:false,error:"",followups_enabled:true,telegram_returns_enabled:false) }
  let fake=Fake(),store=CollaborationStore(service:Fake(),defaults:defaults,notifications:false)
  precondition(store.accept(state(9)));precondition(!store.accept(state(2)));precondition(store.state?.revision==9)
  let wire=CollaborationMutation(action:"commit",expected_revision:7,connection_id:"connection",action_text:"My exact decision",owner:"together",review_condition:"When we can compare")
  precondition(wire.body["review_at"]==nil && wire.body["expected_revision"] as? Int==7)
  let a=CollaborationStore(service:fake,defaults:defaults,notifications:false)
  a.saveDraft(["text":"My exact decision","revision":"7"],name:"commit.connection")
  a.saveDraft(["text":"Another unsent idea"],name:"goal.new")
  precondition(!(await a.submit(wire,draftName:"commit.connection")));precondition(a.pending==[wire] && !a.canEdit)
  let restored=CollaborationStore(service:fake,defaults:defaults,notifications:false)
  precondition(restored.pending==[wire])
  precondition(!(await restored.submit(CollaborationMutation(action:"refresh"))))
  fake.result = .init(ok:true,state:nil);await restored.retry();precondition(restored.pending==[wire])
  fake.result = .init(ok:true,state:state(10));await restored.load()
  precondition(restored.pending.isEmpty && fake.requests.allSatisfy{$0==wire})
  precondition(restored.draft("commit.connection")==nil && restored.draft("goal.new")?["text"]=="Another unsent idea")
  restored.saveDraft(["text":"stale view callback","request_id":wire.event_id],name:"commit.connection")
  precondition(restored.draft("commit.connection")==nil)
  let oldResult=Data(#"{"id":"r","agreement_id":"a","title":"Draft","body":"Prepared","status":"prepared","evidence":[],"created_at":"now"}"#.utf8)
  precondition(try JSONDecoder().decode(CollaborationState.Result.self,from:oldResult).goal_id==nil)
  fake.result = .init(ok:false,error:"stale target",state:state(11))
  _ = await restored.submit(CollaborationMutation(action:"goal",expected_revision:1,goal_id:"old",title:"draft",outcome:"outcome",why:"why"))
  precondition(restored.canEdit && restored.error=="stale target" && restored.state?.revision==11)
  restored.saveDraft(["text":"keep every word","revision":"1"],name:"goal")
  precondition(restored.draft("goal")?["text"]=="keep every word")
  fake.suspend=true;fake.result = .init(ok:true,state:state(13))
  let allow=Task {await restored.submit(CollaborationMutation(action:"settings",followups_enabled:true,telegram_returns_enabled:false))}
  while fake.waiter==nil{await Task.yield()}
  await restored.stopReturns();precondition(restored.locallyStopped && restored.pending.count==2)
  fake.waiter?.resume(returning:.init(ok:true,state:state(12)));_ = await allow.value
  precondition(restored.locallyStopped && restored.pending.isEmpty && fake.requests.last?.followups_enabled==false)
  var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(secondsFromGMT:0)!
  let now=ThoughtReturnPolicy.date("2026-09-07T08:00:00Z")!
  var candidate=CollaborationState.Followup(id:"one",title:"Title",message:"Prepared",reason:"Agreed condition",not_before:"2026-09-07T08:30:00Z",expires_at:"2026-09-08T12:00:00Z",goal_id:"g",connection_id:"c",agreement_id:"a",revision:2)
  precondition(CollaborationNotifier.scheduleDate(candidate,now:now,calendar:cal)==ThoughtReturnPolicy.date("2026-09-07T09:00:00Z"))
  candidate.not_before="2026-09-07T19:30:00Z"
  precondition(CollaborationNotifier.scheduleDate(candidate,now:now,calendar:cal)==ThoughtReturnPolicy.date("2026-09-08T09:00:00Z"))
  candidate.expires_at="2026-09-07T22:00:00Z";precondition(CollaborationNotifier.scheduleDate(candidate,now:now,calendar:cal)==nil)
  let key="alicia.collaboration.notification."
  for name in UserDefaults.standard.dictionaryRepresentation().keys where name.hasPrefix(key){UserDefaults.standard.removeObject(forKey:name)}
  defer{for name in UserDefaults.standard.dictionaryRepresentation().keys where name.hasPrefix(key){UserDefaults.standard.removeObject(forKey:name)}}
  let center=UNUserNotificationCenter.shared
  let tomorrow=Calendar.current.date(byAdding:.day,value:1,to:Date())!
  let clock=Calendar.current.date(bySettingHour:10,minute:0,second:0,of:tomorrow)!
  var payload=state(20)
  candidate.not_before=ISO8601DateFormatter().string(from:clock.addingTimeInterval(300));candidate.expires_at=nil
  payload.followup=candidate
  CollaborationNotifier.allow();await CollaborationNotifier.sync(payload,now:{clock})
  await CollaborationNotifier.sync(payload,now:{clock});precondition(center.requests.count==1)
  precondition(center.requests[0].content.userInfo["agreementID"]=="a")
  // Another purposeful candidate can schedule the same day.
  payload.followup!.id="two";await CollaborationNotifier.sync(payload,now:{clock});precondition(center.requests.count==2)
  payload.followup!.id="one";await CollaborationNotifier.sync(payload,now:{clock});precondition(center.requests.count==3)
  var stale=payload;stale.revision=19;stale.followup!.id="older";await CollaborationNotifier.sync(stale,now:{clock});precondition(center.requests.count==3)
  center.suspend=true;payload.followup!.id="cancelled"
  let waiting=Task{await CollaborationNotifier.sync(payload,now:{clock})}
  while center.waiter==nil{await Task.yield()}
  CollaborationNotifier.stop();center.waiter?.resume(returning:.init(authorizationStatus:.authorized));await waiting.value
  precondition(center.requests.count==3)
  print("19 collaboration checks passed: wire, revision guard, uncertain save, immutable restore, reentrancy, malformed success, acknowledgment, rejection, drafts, later stop, quiet deferral, expiry, same-day purposeful returns, stale notification cancellation, confirmed draft cleanup, late draft callback, legacy result decode, stale scheduler snapshot, cancelled candidate can return")
 }
}
'''
# Await values before using precondition autoclosures.
program=program.replace('precondition(!(await a.submit(wire,draftName:"commit.connection")))','let first = await a.submit(wire,draftName:"commit.connection");precondition(!first)').replace('precondition(!(await restored.submit(CollaborationMutation(action:"refresh"))))','let second = await restored.submit(CollaborationMutation(action:"refresh"));precondition(!second)').replace('precondition(try JSONDecoder().decode(CollaborationState.Result.self,from:oldResult).goal_id==nil)','let decodedResult = try JSONDecoder().decode(CollaborationState.Result.self,from:oldResult);precondition(decodedResult.goal_id==nil)')
with tempfile.TemporaryDirectory(prefix='alicia-collaboration-check-') as tmp:
 p=Path(tmp);source=p/'Checks.swift';source.write_text(models+'\n'+notifier+'\nenum ThoughtReturnPolicy'+policy+'\n'+program)
 env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
 subprocess.run(['xcrun','swiftc','-parse-as-library',str(source),'-o',str(p/'checks')],env=env,check=True)
 subprocess.run([str(p/'checks')]+sys.argv[1:],check=True)
