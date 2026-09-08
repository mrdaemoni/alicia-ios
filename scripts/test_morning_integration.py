#!/usr/bin/env python3
"""Compile actual morning store methods and playlist conversion with inert playback."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
a=(root/'Alicia/Core/AppStore.swift').read_text()
methods=a[a.index('    var morningBriefing:'):a.index('    /// Her weekly mind note.')]
m=(root/'Alicia/Core/Models.swift').read_text()
playlist=m[m.index('struct Playlist:'):m.index('/// A piece of audio Alicia')]
r=(root/'Alicia/Core/SpeechReader.swift').read_text()
readable=r[r.index('struct Readable:'):r.index('extension String')]
featured=m[m.index('struct FeaturedSynthesis:'):m.index('// In an extension so the memberwise') ]
program='''import Foundation
struct SpeechChunk: Hashable { var url:URL; var duration:TimeInterval }
'''+(root/'Alicia/Core/MorningBriefing.swift').read_text()+readable+playlist+featured+'''
@MainActor final class FakeService {
 var value:MorningBriefing?
 func morningBriefing() async -> MorningBriefing? { value }
}
@MainActor final class Reader { var current:Readable?; var isSpeaking=false }
enum Section {case us,studio}
@MainActor final class Store {
 let service=FakeService();let reader=Reader();var selectedSection=Section.us
 func readAloud(_ item:Readable) { if reader.current?.id == item.id {reader.isSpeaking.toggle()} else {reader.current=item;reader.isSpeaking=true} }
'''+methods+'''}
@main struct Checks {
 @MainActor static func main() async {
  let store=Store()
  let b=MorningBriefing(id:"record-id", day:"2026-09-08",title:"Morning",text:"Whole saved script",status:"ready",audio_url:"https://fixture.invalid/api/morning_briefing/audio/record-id.m4a?token=fixture",duration:307,playlist_id:"exact-playlist")
  store.service.value=b;await store.refreshMorningBriefing()
  precondition(store.morningBriefing == b && !store.morningBriefingRefreshing)
  precondition(store.reader.current == nil && store.selectedSection == .us)
  store.service.value=nil;await store.refreshMorningBriefing();precondition(store.morningBriefing == b)
  store.toggleMorningBriefing(b);precondition(store.playingMorningBriefingID == b.id)
  let item=Playlist.Item(id:b.id,kind:"note",title:b.title,body:b.text,source:"alicia_morning_briefing",duration:b.duration,speechChunks:[SpeechChunk(url:URL(string:b.audio_url)!,duration:b.duration)])
  precondition(item.readable == store.reader.current && item.readable.episodeID == nil)
  let opened=FeaturedSynthesis(title:item.title,excerpt:"",body:item.body,date:item.source,speechChunks:item.speechChunks,speechDuration:item.duration,stableReadingID:item.readable.stableID)
  precondition(opened.readable.id == item.readable.id)
  store.readAloud(opened.readable);precondition(!store.reader.isSpeaking && store.reader.current?.id == item.readable.id)
  store.readAloud(opened.readable);precondition(store.reader.isSpeaking)
  store.toggleMorningBriefing(b);precondition(store.playingMorningBriefingID == nil)
  let before=store.reader.current
  store.toggleMorningBriefing(MorningBriefing(id:"missing",status:"preparing"));precondition(store.reader.current == before)
  store.openMorningPlaylist("exact-playlist");precondition(store.morningPlaylistID == "exact-playlist" && store.selectedSection == .studio)
  print("8 morning integration checks passed: read-only refresh, failed refresh retention, shared playback identity, pause, not-ready, episode separation, exact playlist route")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='morning-integration-') as t:
 p=Path(t)/'check.swift';p.write_text(program);out=Path(t)/'check'
 subprocess.run(['swiftc','-parse-as-library',str(p),'-o',str(out)],check=True)
 subprocess.run([str(out)],check=True)
