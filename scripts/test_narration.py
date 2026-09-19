#!/usr/bin/env python3
"""Compile the production alignment and continuation models with inert values."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
source='''import Foundation
struct SpeechChunk { var url: URL; var duration: Double; var text: String = ""; var cues:[NarrationCue] = []; var timingStatus="unavailable" }
struct Track { var title:String=""; var fileName:String?="fixture"; var season:Int=0; var episode:Int=0; var label:String?; var series:String="main"; var collection:String="" }
'''+(root/'Alicia/Core/NarrationDocument.swift').read_text()+(root/'Alicia/Core/EpisodeContinuation.swift').read_text()+'''
func check(_ ok: Bool, _ message: String) { precondition(ok, message) }
let text="Café 😀 waits.\\n\\nThen listen."
let chunk=SpeechChunk(url:URL(string:"https://fixture.invalid")!,duration:4,text:text,cues:[
 NarrationCue(start:0,end:1,text:"Café",start_char:0,end_char:4),
 NarrationCue(start:1,end:2,text:"😀",start_char:5,end_char:6),
 NarrationCue(start:2,end:3,text:"Then",start_char:15,end_char:19)],timingStatus:"ready")
let doc=NarrationDocument(text:text,chunks:[chunk])
check(doc.paragraphs.map(\\.text).joined(separator:"\\n\\n") == text, "Paragraphs preserve exact original Unicode")
check(doc.paragraphs[0].spans.count == 2, "Python scalar offsets survive emoji and accents")
check(doc.paragraphs[1].spans.count == 1, "Cue continues into later paragraph")
var mismatched=chunk; mismatched.text="Someone else's text"
check(!NarrationDocument(text:text,chunks:[mismatched]).hasWordTiming,"Mismatched text cannot acquire word timing")
var invalid=chunk; invalid.cues=[NarrationCue(start:0,end:9,text:"Café",start_char:0,end_char:4)]
check(!NarrationDocument(text:text,chunks:[invalid]).hasWordTiming,"Cue outside measured duration rejected")
invalid.cues=[NarrationCue(start:0,end:1,text:"Cafe",start_char:0,end_char:4)]
check(!NarrationDocument(text:text,chunks:[invalid]).hasWordTiming,"Different word rejected")
invalid=chunk;invalid.timingStatus="pending"
check(!NarrationDocument(text:text,chunks:[invalid]).hasWordTiming,"Pending timing must not highlight words")
check(NarrationDocument(text:text,chunks:[invalid]).paragraphs.first?.chunkStart == 0,"Chunk focus survives unavailable word timing")
let old=EpisodePlaybackReceipt(episode_id:"S16E03",observed_at:"2026-09-10T16:00:00Z")
let recent=EpisodePlaybackReceipt(episode_id:"S16E04",observed_at:"2026-09-11T16:00:00Z")
check(EpisodeContinuation.latest(local:old,server:recent)?.episode_id=="S16E04","Old offline receipt cannot displace newer server playback")
check(EpisodeContinuation.latest(local:recent,server:old)?.episode_id=="S16E04","New actual local playback survives stale server response")
let tracks=[Track(season:17,episode:1,label:"S17E01"),Track(season:16,episode:5,label:"S16E05"),Track(season:16,episode:4,label:"S16E04")]
check(EpisodeContinuation.next(after:"S16E04",tracks:tracks)?.label=="S16E05","Next is chronological despite reversed library ordering")
check(EpisodeContinuation.next(after:"S16E05",tracks:tracks)?.label=="S17E01","Cross season continuation")
check(EpisodeContinuation.next(after:"S17E01",tracks:tracks)==nil,"Last published episode has no invented successor")
check(EpisodeContinuation.next(after:"unknown",tracks:tracks)==nil,"Unknown episode has no guessed successor")
print("14 narration and continuation checks passed")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'check.swift';p.write_text(source)
 subprocess.run(['swiftc',str(p),'-o',d+'/checks'],check=True)
 subprocess.run([d+'/checks'],check=True)
