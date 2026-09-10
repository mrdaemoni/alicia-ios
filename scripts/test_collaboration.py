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
  let upgradeSuite=suite+".upgrade",upgrade=UserDefaults(suiteName:suite+".upgrade")!,upgradeService=Fake()
  defer {upgrade.removePersistentDomain(forName:upgradeSuite)}
  upgrade.set(true,forKey:"alicia.thoughtReturn.locallyStopped")
  let migrated=CollaborationStore(service:upgradeService,defaults:upgrade,notifications:false)
  precondition(migrated.locallyStopped)
  upgradeService.result = .init(ok:true,state:state(1))
  _ = await migrated.submit(CollaborationMutation(action:"settings",followups_enabled:true,telegram_returns_enabled:false))
  CollaborationReturnPreferences.migrateLegacyStop(in:upgrade)
  precondition(!migrated.locallyStopped)
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
  let section = WorkReviewSection(id:"q7",title:"Q7",kind:"question",text:"The exact question?\n",content_hash:"hash",review:.empty)
  let answer = section.mutation(resultID:"result",verdict:"answer",text:"My entire answer",revision:4)
  precondition(answer.body["result_id"] as? String == "result" && answer.body["section_id"] as? String == "q7")
  precondition(answer.body["content_hash"] as? String == "hash" && answer.expected_revision == 4)
  let roundTripAnswer = try JSONDecoder().decode(CollaborationMutation.self,from:JSONEncoder().encode(answer))
  precondition(roundTripAnswer == answer)
  restored.saveDraft(["text":"My entire answer", "mode":"answer", "revision":"4"],name:"work.result.q7.answer")
  restored.saveDraft(["text":"A distinct edit", "mode":"edit", "revision":"4"],name:"work.result.q7.edit")
  fake.result = nil
  _ = await restored.submit(answer,draftName:"work.result.q7.answer")
  let restart = CollaborationStore(service:fake,defaults:defaults,notifications:false)
  precondition(restart.pending == [answer] && restart.draft("work.result.q7.answer")?["text"] == "My entire answer")
  fake.result = .init(ok:true,state:state(11)); await restart.retry()
  precondition(restart.draft("work.result.q7.answer") == nil && restart.draft("work.result.q7.edit")?["text"] == "A distinct edit")
  await restored.retry()
  let target = WorkDialogueContext(goal_id:"goal",result_id:"result",section_id:"q7",content_hash:"hash",goalTitle:"Enough",sectionTitle:"Q7",quote:"Original question")
  restart.rememberDialogueContext(target,replyID:"saved-reply")
  precondition(CollaborationStore(service:fake,defaults:defaults,notifications:false).dialogueContext(for:"saved-reply") == target)
  restart.dialogueContext = target
  precondition(target.wire["quote"] == nil && target.wire.count == 4)
  let reopened = CollaborationStore(service:fake,defaults:defaults,notifications:false)
  precondition(reopened.dialogueContext == target)
  reopened.dialogueContext = nil
  precondition(CollaborationStore(service:fake,defaults:defaults,notifications:false).dialogueContext == nil)
  precondition(WorkReviewProgress(total:3,reviewed:1,questions:1,answered:0).remaining == 2)
  let oldResult=Data(#"{"id":"r","agreement_id":"a","title":"Draft","body":"Prepared","status":"prepared","evidence":[],"created_at":"now"}"#.utf8)
  precondition(try JSONDecoder().decode(CollaborationState.Result.self,from:oldResult).goal_id==nil)
  fake.result = .init(ok:false,error:"stale target",state:state(11))
  _ = await restored.submit(CollaborationMutation(action:"goal",expected_revision:1,goal_id:"old",title:"draft",outcome:"outcome",why:"why"))
  precondition(restored.canEdit && restored.error=="stale target" && restored.state?.revision==11)
  let rejection = Data(#"{"ok":false,"error":"stale target"}"#.utf8)
  fake.result = CollaborationResponse.decode(rejection,status:400)
  _ = await restored.submit(CollaborationMutation(action:"goal",expected_revision:1,goal_id:"old",title:"retained",outcome:"outcome"))
  precondition(restored.canEdit && restored.error=="stale target")
  for status in [401,403,429,500,503] { precondition(CollaborationResponse.decode(rejection,status:status)==nil) }
  precondition(CollaborationResponse.decode(rejection,status:nil)==nil)
  for bytes in [Data("not json".utf8),Data(#"{"ok":true}"#.utf8),Data(#"{"ok":false}"#.utf8)] { precondition(CollaborationResponse.decode(bytes,status:400)==nil) }
  let unconfirmed = CollaborationMutation(action:"refresh")
  fake.result = CollaborationResponse.decode(rejection,status:500)
  _ = await restored.submit(unconfirmed)
  precondition(restored.pending==[unconfirmed] && !restored.canEdit)
  let success = try JSONEncoder().encode(CollaborationResponse(ok:true,state:state(11)))
  fake.result = CollaborationResponse.decode(success,status:200)
  await restored.retry();precondition(restored.pending.isEmpty)
  restored.saveDraft(["text":"My unsaved revision","revision":"1"],name:"reload")
  fake.value=nil
  let failedReload = await restored.reloadDraft("reload")
  precondition(!failedReload && restored.draft("reload")?["text"]=="My unsaved revision" && restored.draft("reload")?["revision"]=="1")
  var refreshed=state(12)
  refreshed.goals=[.init(id:"old",title:"Current server goal",outcome:"Current outcome",why:"Current reason",status:"active",priority:"normal",revision:12,created_at:"then",updated_at:"now")]
  fake.value=refreshed
  let freshReload = await restored.reloadDraft("reload")
  precondition(freshReload && restored.draft("reload")==nil && restored.state?.goals.first?.revision==12)
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
  let migrationKeys=["alicia.collaboration.stopped","alicia.collaboration.legacyStopMigrated","alicia.thoughtReturn.locallyStopped"]
  for name in migrationKeys {UserDefaults.standard.removeObject(forKey:name)}
  defer {for name in migrationKeys {UserDefaults.standard.removeObject(forKey:name)}}
  for name in UserDefaults.standard.dictionaryRepresentation().keys where name.hasPrefix(key){UserDefaults.standard.removeObject(forKey:name)}
  defer{for name in UserDefaults.standard.dictionaryRepresentation().keys where name.hasPrefix(key){UserDefaults.standard.removeObject(forKey:name)}}
  let center=UNUserNotificationCenter.shared
  let tomorrow=Calendar.current.date(byAdding:.day,value:1,to:Date())!
  let clock=Calendar.current.date(bySettingHour:10,minute:0,second:0,of:tomorrow)!
  var payload=state(20)
  candidate.not_before=ISO8601DateFormatter().string(from:clock.addingTimeInterval(300));candidate.expires_at=nil
  payload.followup=candidate
  UserDefaults.standard.set(true,forKey:"alicia.thoughtReturn.locallyStopped")
  await CollaborationNotifier.sync(payload,now:{clock})
  precondition(center.requests.isEmpty && UserDefaults.standard.bool(forKey:"alicia.collaboration.stopped"))
  CollaborationNotifier.allow();await CollaborationNotifier.sync(payload,now:{clock})
  precondition(!UserDefaults.standard.bool(forKey:"alicia.collaboration.stopped"))
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
  var multiple=state(30)
  multiple.goals = [
   .init(id:"goal-low",title:"Family time",outcome:"Protected evenings",why:"",status:"active",priority:"less",revision:28,created_at:"then",updated_at:"now"),
   .init(id:"goal-high",title:"Writing",outcome:"A clear draft",why:"",status:"active",priority:"more",revision:29,created_at:"then",updated_at:"now"),
   .init(id:"goal-normal",title:"Learning",outcome:"Useful connections",why:"",status:"active",priority:"normal",revision:30,created_at:"then",updated_at:"now"),
   .init(id:"paused",title:"Paused",outcome:"Later",why:"",status:"paused",priority:"more",revision:27,created_at:"then",updated_at:"now")]
  fake.value=multiple
  let reloaded=CollaborationStore(service:fake,defaults:defaults,notifications:false)
  await reloaded.load()
  precondition(reloaded.state?.activeGoals.map(\.id)==["goal-high","goal-normal","goal-low"])
  precondition(reloaded.state?.goals.count==4)
  let newGoal=CollaborationMutation(action:"goal",title:"Fourth goal",outcome:"A separate outcome",priority:"normal",status:"active")
  precondition(newGoal.body["goal_id"]==nil && newGoal.body["expected_revision"]==nil)
  let oldRoute=Data(#"{"id":"old","candidateID":"","goalID":"goal-high","connectionID":"","agreementID":""}"#.utf8)
  let restoredRoute=try JSONDecoder().decode(CollaborationRoute.self,from:oldRoute)
  precondition(restoredRoute.newGoal==nil && restoredRoute.goalID=="goal-high")
  let createRoute=CollaborationRoute(newGoal:true)
  let decodedRoute=try JSONDecoder().decode(CollaborationRoute.self,from:JSONEncoder().encode(createRoute))
  precondition(decodedRoute.newGoal==true && decodedRoute.goalID.isEmpty)
  print("5 concurrent-goal checks passed: sorted active goals, retained paused goals, creation does not target an existing goal, historical route decode, direct new-goal route")
  print("30 collaboration checks passed: wire, revision guard, uncertain save, immutable restore, reentrancy, malformed success, acknowledgment, rejection, drafts, later stop, quiet deferral, expiry, same-day purposeful returns, stale notification cancellation, confirmed draft cleanup, late draft callback, legacy result decode, stale scheduler snapshot, cancelled candidate can return, HTTP400 rejection, HTTP200 acknowledgment, auth and server uncertainty, malformed validation uncertainty, HTTP500 keeps receipt, failed reload retains draft, fresh reload advances revision, foreground stop migration, deliberate allow after migration, background stop migration, background allow after migration")
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
