#!/usr/bin/env python3
"""Exercise actual Studio takeover methods with inert audio IO."""
from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[1]; source=(r/'Alicia/Core/AppStore.swift').read_text()
def method(name):
 start=source.index('    '+name);opening=source.index('{',start);depth=1;end=opening+1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end].replace('private func','func')
methods='\n'.join(method(x) for x in ['func play(_ track:','private func takePlaybackFromReader(','private func seekStudio(','func togglePlay()','private func pauseForReading()'])
program='''import Foundation
struct Track {var id:String;var label:String?;var duration:Double=300;var fileName:String?="https://fixture.invalid/audio"}
struct Readable {var episodeID:String?}
final class Reader {var current:Readable?;var elapsed=0.0;var isActive:Bool {current != nil};func stop(){current=nil}}
struct CMTime {var seconds:Double;var preferredTimescale:Int}
final class Player {var rate:Float=0;var seconds=0.0;var beforePlay:(()->Void)?;func play(){beforePlay?();rate=1};func pause(){rate=0};func seek(to time:CMTime){seconds=time.seconds}}
final class Store {
 var nowPlaying:Track?;var isPlaying=false;var player:Player?;let reader=Reader();var progress=0.0;var playbackRate:Float=1.5;var ticker:Task<Void,Never>?
 func chooseEpisode(_ track:Track){}
 func flushEpisodePlayback(){}
 func publishNowPlaying(){}
 func startTicker(){}
 func stopPlayer(){player=nil}
 func startPlayer(url:URL,at position:Double=0){player=Player();player?.seconds=position;player?.beforePlay={[weak self] in precondition(self?.reader.isActive==false,"Two audio owners")};player?.play()}
'''+methods+'''
}
let store=Store(), first=Track(id:"one",label:"S16E04"), second=Track(id:"two",label:"S16E05")
store.play(first);precondition(store.isPlaying && store.player?.rate != 0)
store.pauseForReading();store.reader.current=Readable(episodeID:first.label);store.reader.elapsed=128
precondition(!store.isPlaying && store.player?.rate==0)
store.togglePlay();precondition(!store.reader.isActive && store.isPlaying && store.player?.seconds==128)
store.pauseForReading();store.reader.current=Readable(episodeID:first.label);store.reader.elapsed=150
store.play(first);precondition(!store.reader.isActive && store.player?.seconds==150)
store.pauseForReading();store.reader.current=Readable(episodeID:first.label);store.reader.elapsed=180
store.play(second);precondition(!store.reader.isActive && store.nowPlaying?.label==second.label && store.player?.seconds==0)
store.pauseForReading();store.reader.current=Readable(episodeID:first.label);store.reader.elapsed=200
store.play(first);precondition(!store.reader.isActive && store.player?.seconds==200)
print("6 actual Studio/reader ownership checks passed")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'check.swift';p.write_text(program);subprocess.run(['swiftc',str(p),'-o',d+'/checks'],check=True);subprocess.run([d+'/checks'],check=True)
