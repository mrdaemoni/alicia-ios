#!/usr/bin/env python3
"""Exercise actual AppStore settings and notifier methods with suspended fake IO."""
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
models=(root/'Alicia/Core/ContextEnrichment.swift').read_text()
store=(root/'Alicia/Core/AppStore.swift').read_text()
start=store.index('    func changeContext('); end=store.index('    private func syncThoughtReturn',start)
change=store[start:end]
notifier=(root/'Alicia/Core/ThoughtReturnNotifier.swift').read_text().replace('import UserNotifications','')
program=r'''
import Foundation
struct UNNotificationSettings {
 enum AuthorizationStatus { case authorized, provisional, denied }
 var authorizationStatus: AuthorizationStatus
}
class UNMutableNotificationContent {
 var title="", body=""
 enum Sound { case `default` }; var sound: Sound?
 var userInfo: [String:String]=[:]
}
struct UNCalendarNotificationTrigger { var dateMatching: DateComponents; var repeats: Bool }
struct UNNotificationRequest { var identifier: String; var content: UNMutableNotificationContent; var trigger: UNCalendarNotificationTrigger }
@MainActor class UNUserNotificationCenter {
 static let instance=UNUserNotificationCenter()
 static func current()->UNUserNotificationCenter { instance }
 var requests:[UNNotificationRequest]=[]
 var removes:[String]=[]
 var waitSettings=false
 var continuation: CheckedContinuation<UNNotificationSettings,Never>?
 func notificationSettings() async -> UNNotificationSettings {
  if waitSettings { return await withCheckedContinuation { continuation=$0 } }
  return UNNotificationSettings(authorizationStatus:.authorized)
 }
 func removePendingNotificationRequests(withIdentifiers ids:[String]) { removes += ids }
 func add(_ request:UNNotificationRequest) async throws { requests.append(request) }
}
@MainActor class Service {
 var waiting: [(ContextChange, CheckedContinuation<ContextChangeResult?,Never>)]=[]
 func changeContext(_ change:ContextChange) async -> ContextChangeResult? {
  await withCheckedContinuation { waiting.append((change,$0)) }
 }
}
@MainActor class Harness {
 var contextActivityRevision=0, contextSettingsRevision=0
 var synced=0
 let service=Service()
 func noteContextActivity() { contextActivityRevision += 1; ThoughtReturnNotifier.cancel() }
 func syncThoughtReturn(_ value:ContextEnrichment) async { synced += 1 }
__CHANGE__
}
@main struct Checks {
 @MainActor static func main() async {
  let key="alicia.thoughtReturn."
  // Run in a dedicated executable-domain suite, never the iOS app defaults.
  for name in UserDefaults.standard.dictionaryRepresentation().keys where name.hasPrefix(key) { UserDefaults.standard.removeObject(forKey:name) }
  defer { for name in UserDefaults.standard.dictionaryRepresentation().keys where name.hasPrefix(key) { UserDefaults.standard.removeObject(forKey:name) } }
  let state=ContextEnrichment(about:[],items:[],reply_id:"",exposure:"",followups_enabled:true)
  ThoughtReturnNotifier.setLocalEnabled(false)
  let h=Harness()
  let allow=Task { await h.changeContext(ContextChange(action:"settings",followups_enabled:true)) }
  while h.service.waiting.isEmpty { await Task.yield() }
  h.noteContextActivity()
  h.service.waiting[0].1.resume(returning:ContextChangeResult(ok:true,context:state))
  _ = await allow.value
  precondition(!ThoughtReturnNotifier.locallyStopped && h.synced==0)
  let a=Task { await h.changeContext(ContextChange(action:"settings",followups_enabled:true)) }
  while h.service.waiting.count<2 { await Task.yield() }
  let b=Task { await h.changeContext(ContextChange(action:"settings",followups_enabled:false)) }
  while h.service.waiting.count<3 { await Task.yield() }
  h.service.waiting[2].1.resume(returning:ContextChangeResult(ok:true,context:state))
  _ = await b.value
  h.service.waiting[1].1.resume(returning:ContextChangeResult(ok:true,context:state))
  _ = await a.value
  precondition(ThoughtReturnNotifier.locallyStopped)
  ThoughtReturnNotifier.setLocalEnabled(true)
  let center=UNUserNotificationCenter.current()
  let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
  var clock=Calendar.current.date(bySettingHour:10,minute:0,second:0,of:Date())!
  do {
   var candidate=state
   candidate.followup = .init(id:"expiry",text:"One test idea",anchor:"Fixture anchor",due_at:formatter.string(from:clock.addingTimeInterval(60)))
   center.waitSettings=true
   let task=Task { await ThoughtReturnNotifier.sync(candidate,now:{ clock }) }
   while center.continuation==nil { await Task.yield() }
   clock=clock.addingTimeInterval(120)
   center.continuation?.resume(returning:UNNotificationSettings(authorizationStatus:.authorized));center.continuation=nil
   await task.value
   precondition(center.requests.isEmpty)
   candidate.followup!.id="cancelled";candidate.followup!.due_at=formatter.string(from:clock.addingTimeInterval(60))
   let cancelled=Task { await ThoughtReturnNotifier.sync(candidate,now:{ clock }) }
   while center.continuation==nil { await Task.yield() }
   ThoughtReturnNotifier.cancel()
   center.continuation?.resume(returning:UNNotificationSettings(authorizationStatus:.authorized));center.continuation=nil
   await cancelled.value
   precondition(center.requests.isEmpty)
   print("4 async context checks passed: allow survives unrelated activity, later stop wins, expired scheduling rejected, cancelled lookup cannot schedule")
  }
 }
}
'''.replace('__CHANGE__',change)
with tempfile.TemporaryDirectory() as td:
 p=Path(td)/'Checks.swift';binary=Path(td)/'ContextLifecycleChecks'
 p.write_text(models+'\n'+notifier+'\n'+program)
 env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
 subprocess.run(['xcrun','swiftc','-parse-as-library',str(p),'-o',str(binary)],env=env,check=True)
 subprocess.run([str(binary)],check=True)
