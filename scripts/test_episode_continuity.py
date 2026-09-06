#!/usr/bin/env python3
"""Exercise actual AppStore topic/draft methods with inert network boundaries."""
from pathlib import Path
import os, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'Alicia/Core/AppStore.swift').read_text()
def section(start,end):
    return source[source.index(start):source.index(end,source.index(start))].replace('private ', '')
choice = section('    func chooseEpisode(', '    func loadEpisodeDay(')
walk = section('    func openWalk(', '    func beginWalkRecording(')
flush = section('    private func flushPlaybackOutbox()', '    // MARK: playlists')
models = (root/'Alicia/Core/EpisodeDay.swift').read_text().split('#if DEBUG')[0]
program = r'''
import Foundation
struct Track { var label: String?; var title: String }
@MainActor final class Service {
 var results:[EpisodeDayResponse?]=[]
 var sent:[String]=[]
 func episodeAction(_ body:[String:Any]) async -> EpisodeDayResponse? {
  sent.append(body["event_id"] as? String ?? "")
  return results.isEmpty ? nil : results.removeFirst()
 }
 func episodeDay(day:String) async -> EpisodeDay? { nil }
}
@MainActor final class Harness {
 let service=Service()
 var playbackFlushing=false, episodeChoiceNeedsRefresh=false
 var episodeDay: EpisodeDay?
 var playbackOutbox:[[String:Any]]=[]
 var walkEpisodeID="", walkDraft="", walkPrompt="", walkRequestID="initial", episodeError=""
 var pendingWalkSave:[String:String]?
 var showWalk=false
 func noteContextActivity() {}
 func awaitEpisodeFrame() {}
 func refreshEpisodeDay() async {}
__FLUSH__
__CHOICE__
__WALK__
}
@main struct Checks {
 @MainActor static func main() async {
  let keys=["alicia.playbackOutbox","alicia.episodeWalkDrafts","alicia.walkEpisodeID","alicia.walkRequestID","alicia.rejectedEpisodeReceipts"]
  for key in keys { UserDefaults.standard.removeObject(forKey:key) }
  defer { for key in keys { UserDefaults.standard.removeObject(forKey:key) } }
  let h=Harness()
  h.chooseEpisode(.init(label:"S1E01",title:"First"))
  precondition(h.episodeDay?.episode?.id == "S1E01" && h.episodeChoiceSyncing)
  precondition(h.episodeDay?.has_playback == false && h.episodeDay?.probes.isEmpty == true)
  precondition(h.playbackOutbox.count==1 && h.playbackOutbox[0]["action"] as? String == "selected")
  h.openWalk(probe:"First question")
  h.walkDraft="My exact first thought"
  let firstID=h.walkRequestID
  h.chooseEpisode(.init(label:"S1E02",title:"Second"))
  h.openWalk(probe:"Second question")
  precondition(h.walkDraft.isEmpty && h.walkEpisodeID=="S1E02" && h.walkPrompt=="Second question")
  h.walkDraft="My second thought"
  h.chooseEpisode(.init(label:"S1E01",title:"First"))
  h.openWalk()
  precondition(h.walkDraft=="My exact first thought" && h.walkPrompt=="First question" && h.walkRequestID==firstID)
  // An old HTTP result cannot replace the pending choice.
  var stale=EpisodeDay.choosing(.init(id:"S1E02",title:"Second",source_paths:[]),previous:nil)
  stale.snapshot_revision=2
  h.acceptEpisodeDay(stale)
  precondition(h.episodeDay?.episode?.id=="S1E01")
  // After the choice is acknowledged, an earlier fetch still cannot win.
  h.playbackOutbox=[]
  var current=EpisodeDay.choosing(.init(id:"S1E01",title:"First",source_paths:[]),previous:nil)
  current.snapshot_revision=3
  h.acceptEpisodeDay(current); h.acceptEpisodeDay(stale)
  precondition(h.episodeDay?.episode?.id=="S1E01")
  h.pendingWalkSave=["text":"Frozen words","episode_id":"S1E01","request_id":"frozen"]
  h.chooseEpisode(.init(label:"S1E02",title:"Second"))
  h.openWalk()
  precondition(h.walkEpisodeID=="S1E01" && h.pendingWalkSave?["request_id"]=="frozen")
  precondition(h.episodeError.contains("Retry it") && h.showWalk)
  let before=h.playbackOutbox.count
  h.chooseEpisode(.init(label:nil,title:"A synthesis"))
  precondition(h.playbackOutbox.count==before)
  let old=Harness()
  old.episodeDay=current; old.episodeDay!.date="2020-01-01"
  old.chooseEpisode(.init(label:"S1E01",title:"First"))
  precondition(old.playbackOutbox.count==1 && old.episodeDay?.date != "2020-01-01")
  let outbox=Harness()
  outbox.playbackOutbox=[["action":"selected","episode_id":"S1E01","event_id":"bad"],
                        ["action":"selected","episode_id":"S1E02","event_id":"good"]]
  outbox.service.results=[EpisodeDayResponse(ok:false,error:"Missing script",retryable:false),EpisodeDayResponse(ok:true,day:stale)]
  await outbox.flushPlaybackOutbox()
  precondition(outbox.playbackOutbox.isEmpty && outbox.service.sent==["bad","good"] && outbox.episodeDay?.episode?.id=="S1E02")
  let uncertain=Harness()
  uncertain.playbackOutbox=[["action":"selected","episode_id":"S1E01","event_id":"uncertain"]]
  uncertain.service.results=[nil]
  await uncertain.flushPlaybackOutbox()
  precondition(uncertain.playbackOutbox.count==1 && uncertain.playbackOutbox[0]["event_id"] as? String == "uncertain")
  uncertain.service.results=[EpisodeDayResponse(ok:false,error:"Temporary storage failure",retryable:true)]
  await uncertain.flushPlaybackOutbox()
  precondition(uncertain.playbackOutbox.count==1)
  let rejected=Harness()
  rejected.episodeDay=current
  rejected.playbackOutbox=[["action":"selected","episode_id":"S1E01","event_id":"rejected"]]
  rejected.service.results=[EpisodeDayResponse(ok:false,error:"Unavailable",retryable:false)]
  await rejected.flushPlaybackOutbox()
  precondition(rejected.episodeDay==nil && rejected.episodeChoiceSyncing)
  rejected.acceptEpisodeDay(stale)
  precondition(!rejected.episodeChoiceSyncing && rejected.episodeDay?.episode?.id=="S1E02")
  print("12 episode checks passed: instant selection, separate drafts, exact restore, pending race, stale fetch, immutable pending save, non-episode ignored")
 }
}
'''.replace('__CHOICE__',choice).replace('__WALK__',walk).replace('__FLUSH__',flush)
with tempfile.TemporaryDirectory(prefix='alicia-episode-checks-') as tmp:
    code=Path(tmp)/'Checks.swift';binary=Path(tmp)/'checks'
    code.write_text(models+program)
    env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['xcrun','swiftc','-parse-as-library',str(code),'-o',str(binary)],env=env,check=True)
    subprocess.run([str(binary)],check=True)
