#!/usr/bin/env python3
"""Actual AppStore.load must publish the library while diagnostics are blocked."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root/'Alicia/Core/AppStore.swift').read_text()
load = source[source.index('    func load() async {'):source.index('    private static func historyDate(')]
program = r'''
import Foundation
struct Message {var id = UUID()}
struct History {var messages:[String] = []}
@MainActor enum ProactiveNotifier {static func markSeen(_ value:[String]) {}}
@MainActor final class Shared {func load() async {}}
@MainActor final class Service {
 var waiting:CheckedContinuation<[String]?,Never>?
 func health() async -> [String]? {await withCheckedContinuation{waiting = $0}}
 func episodeDay(day:String) async -> String? {"day"}
 func conversationHistory() async -> History? {nil}
 func thoughts() async -> [String]? {["thought"]}
 func tracks() async -> [String]? {["track"]}
 func gallery() async -> [String]? {["gallery"]}
 func proactive(limit:Int) async -> [String] {[]}
 func modeState() async -> (String,Int) {("idle",0)}
 func syntheses() async -> [String] {["synthesis"]}
 func homeContext() async -> String? {"home"}
 func playlists() async -> [String] {["playlist"]}
 func thinkers() async -> String? {"thinkers"}
}
@MainActor final class Harness {
 let service = Service(), collaboration = Shared()
 final class Steering { func flush() {} }
 let briefingSteering = Steering()
 var messages:[Message] = [], isStreaming = false
 var episodeDay:String?, thinkerNetwork:String?, homeContext:String?
 var thoughts:[String] = [], tracks:[String] = [], gallery:[String] = [], health:[String] = [], syntheses:[String] = [], playlists:[String] = [], proactiveFeed:[String] = []
 var thinkingMode = "", walkWords = 0
 func refreshPresence() async {}
 func refreshMorningBriefing() async {}
 func refreshVoiceArchive() async {}
 func refreshEpisodeThinkers() async {}
 func acceptEpisodeDay(_ day:String) {episodeDay = day}
 func flushPlaybackOutbox() async {}
 func publishWidgetCache(hasFreshData:Bool) {}
 func historyMessage(_ row:String) -> Message {.init()}
__LOAD__
}
@main struct Checks {
 @MainActor static func main() async {
  let h = Harness(); var loaded = false
  Task {await h.load(); loaded = true}
  for _ in 0..<100 {if loaded {break}; try? await Task.sleep(for:.milliseconds(5))}
  precondition(loaded, "health diagnostics still gate startup")
  precondition(h.playlists == ["playlist"] && h.thinkingMode == "idle" && h.homeContext == "home")
  precondition(h.health.isEmpty && h.service.waiting != nil)
  h.service.waiting?.resume(returning:["diagnostics"])
  for _ in 0..<100 {if !h.health.isEmpty {break}; await Task.yield()}
  precondition(h.health == ["diagnostics"])
  print("Startup passed: library, episode, home and mode publish before blocked diagnostics; diagnostics arrive independently.")
 }
}
'''.replace('__LOAD__',load)
with tempfile.TemporaryDirectory(prefix='alicia-startup-') as directory:
    directory = Path(directory); source = directory/'checks.swift'; source.write_text(program)
    binary = directory/'checks'
    env = dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['xcrun','swiftc','-parse-as-library',str(source),'-o',str(binary)],check=True,env=env)
    subprocess.run([str(binary)],check=True,env=env,timeout=10)
