#!/usr/bin/env python3
"""CL-20261126-us-day-episodes: the afternoon and evening on Us.

Compiles the real DayEpisode model, the playlist item's reading identity and the
store's day-episode methods with an inert reader, then checks the backend's real
payload shapes, status wording, refresh retention and that the Us card and the
Studio item are one reading. Invented fixtures only (this repo is public).
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
store = (root / 'Alicia/Core/AppStore.swift').read_text()
methods = store[store.index('    // MARK: Afternoon and Evening with Alicia on Us'):
                store.index('    // MARK: playlists — the listening queues (Studio)')]
models = (root / 'Alicia/Core/Models.swift').read_text()
playlist = models[models.index('struct Playlist:'):models.index('/// A piece of audio Alicia')]
reader_source = (root / 'Alicia/Core/SpeechReader.swift').read_text()
readable = reader_source[reader_source.index('struct Readable:'):reader_source.index('extension String')]

# Wiring the compiled checks cannot see: the Us page, refresh points and the live service.
home = (root / 'Alicia/Features/Home/EpisodeDayView.swift').read_text()
assert home.index('MorningBriefingView(') < home.index('DayEpisodeView(') < home.index('MindBodyOverview()')
assert 'store.dayEpisodes.filter { $0.isToday(clock.date) }' in home
assert 'onTogglePlayback: store.toggleDayEpisode' in home
task_line = next(line for line in home.splitlines() if line.strip().startswith('.task { await store.refreshIntelligenceMode()'))
pull_line = next(line for line in home.splitlines() if line.strip().startswith('.refreshable {'))
assert 'await store.refreshDayEpisodes()' in task_line and 'await store.refreshDayEpisodes()' in pull_line
load = store[store.index('    func load() async {'):]
assert 'Task { await refreshDayEpisodes() }' in load[:load.index('\n    }\n')]
recovery = store[store.index('    func reprobeConnection() async {'):]
recovery = recovery[:recovery.index('\n    }\n')]
assert 'async let days = self.service.dayEpisodes()' in recovery and 'self.acceptDayEpisodes(freshDays)' in recovery
live = (root / 'Alicia/Core/LiveAliciaService.swift').read_text()
fetch = live[live.index('    func dayEpisodes() async -> DayEpisodes? {'):]
fetch = fetch[:fetch.index('\n    }\n')]
assert 'fetchOne("/api/day_episodes", reportsConnection: false)' in fetch
assert 'episode.audio_url = mediaURL(episode.audio_url)' in fetch and 'guard let url = mediaURL(chunk.url)' in fetch
service = (root / 'Alicia/Core/AliciaService.swift').read_text()
assert '    func dayEpisodes() async -> DayEpisodes?\n' in service
view = (root / 'Alicia/Features/Home/DayEpisodeView.swift').read_text()
assert 'BriefingStage' not in view and 'Feedback' not in view and 'Steering' not in view

program = '''import Foundation
import CryptoKit
struct SpeechChunk: Hashable { var url:URL; var duration:TimeInterval; var text:String = ""; var cues:[NarrationCue] = []
 var timingStatus:String = "unavailable"; var spokenText:String = ""; var speechBackend:String = ""
 var clipStart:TimeInterval = 0; var clipEnd:TimeInterval? = nil; var piece:BriefingPiece? = nil }
''' + (root / 'Alicia/Core/NarrationDocument.swift').read_text().split('/// Exact text')[0] \
    + (root / 'Alicia/Core/MorningBriefing.swift').read_text() \
    + (root / 'Alicia/Core/BriefingSteering.swift').read_text() \
    + (root / 'Alicia/Core/DayEpisodes.swift').read_text() + readable + playlist + '''
@MainActor final class FakeService {
 var value:DayEpisodes?
 var calls=0
 func dayEpisodes() async -> DayEpisodes? { calls += 1; return value }
}
@MainActor final class Reader { var current:Readable?; var isSpeaking=false }
@MainActor final class Store {
 let service=FakeService();let reader=Reader()
 var showBriefingStage=false
 func readAloud(_ item:Readable) { if reader.current?.id == item.id {reader.isSpeaking.toggle()} else {reader.current=item;reader.isSpeaking=true} }
''' + methods + '''}
let payload = #"""
{"day":"2026-11-26","timezone":"America/Los_Angeles","episodes":[
 {"id":"afternoon-id","day":"2026-11-26","slot":"afternoon","timezone":"America/Los_Angeles","title":"What the room leaves open",
  "text":"Whole saved script.","status":"ready","audio_url":"/api/day_episodes/audio/afternoon-id.m4a","duration":418.69,
  "playlist_id":"pl_afternoon_with_alicia","error":"","season":22,"starts_at":"13:00","word_count":983,
  "prepared_at":"2026-11-26T21:03:21+00:00","ready_at":"2026-11-26T21:05:21+00:00","script_model":"fixture",
  "audio_backend":"gemini","voice":"fixture","script_sha256":"fixture","reactions":15,
  "follows":[{"slot":"morning","id":"m","day":"2026-11-26","title":"Morning"}],
  "sources":[{"id":"s1","kind":"synthesis","title":"Fixture synthesis","path":"Alicia/Wisdom/x.md","excerpt":"A passage.","sha256":"b","line_start":3}],
  "speech":{"chunks":[{"url":"/api/reading/c0.m4a","duration":13.9,"text":"What the room leaves open.","timing_status":"ready",
   "cues":[{"start":0.1,"end":0.4,"text":"What","start_char":0,"end_char":4}]}],"duration":418.69,"spoken_text":"What the room leaves open.\\n\\nWhole saved script."}},
 {"id":"evening-id","day":"2026-11-26","slot":"evening","timezone":"America/Los_Angeles","title":"","text":"","status":"scheduled",
  "audio_url":"","duration":0.0,"playlist_id":"pl_evening_with_alicia","error":"","sources":[],"season":0,"starts_at":"18:30"}]}
"""#
@main struct Checks {
 @MainActor static func main() async {
  let english = Locale(identifier: "en_US")
  let decoded = try! JSONDecoder().decode(DayEpisodes.self, from: Data(payload.utf8))
  precondition(decoded.day == "2026-11-26" && decoded.episodes.map(\\.slot) == ["afternoon", "evening"])
  let afternoon = decoded.episodes[0], evening = decoded.episodes[1]
  precondition(afternoon.hasPlayableAudio && afternoon.hasText && afternoon.hasPlaylist)
  precondition(afternoon.durationLabel == "6:59" && afternoon.spokenDuration == "6 minutes, 59 seconds")
  precondition(afternoon.sources.first?.title == "Fixture synthesis" && afternoon.speech?.chunks?.first?.cues?.count == 1)
  precondition(afternoon.slotName == "Afternoon with Alicia" && afternoon.readingID == "day:afternoon-id")
  precondition(afternoon.availabilityText(locale: english) == "Ready to listen.")
  precondition(!evening.hasPlayableAudio && !evening.hasText && evening.speech == nil)
  precondition(evening.displayTitle == "Evening with Alicia")
  // Apple writes a narrow no-break space before the day period.
  let start = evening.availabilityText(locale: english).replacingOccurrences(of: "\\u{202F}", with: " ")
  precondition(start == "Prepared from 6:30 PM.", start)
  var odd = evening; odd.starts_at = "25:00"; precondition(odd.availabilityText(locale: english) == "Prepared later today.")
  odd.starts_at = ""; precondition(odd.startLabel(locale: english) == nil)
  let failed = try! JSONDecoder().decode(DayEpisode.self, from: Data(#"{"id":"f","slot":"evening","status":"failed","error":"The episode script could not be prepared. It will retry.","sources":"not a list"}"#.utf8))
  precondition(failed.sources.isEmpty && failed.availabilityText() == "The episode script could not be prepared. It will retry.")
  precondition(DayEpisode(id:"p",status:"preparing").availabilityText() == "Being prepared now.")
  precondition(DayEpisode(id:"u",status:"unavailable").availabilityText() == "Not available right now.")
  let missing = DayEpisode(id:"a",status:"audio_unavailable",duration:0,error:"The saved script is safe; its audio needs to be restored.")
  precondition(!missing.hasPlayableAudio && missing.availabilityText() == missing.error)
  precondition(!DayEpisode(id:"r",status:"ready",audio_url:"/x.m4a",duration:0).hasPlayableAudio)
  let empty = try! JSONDecoder().decode(DayEpisodes.self, from: Data("{}".utf8)); precondition(empty.episodes.isEmpty)
  var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
  let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 12))!
  precondition(afternoon.isToday(noon, calendar: calendar))
  precondition(!afternoon.isToday(calendar.date(byAdding: .day, value: 1, to: noon)!, calendar: calendar))
  precondition(!DayEpisode(id:"x", day:"26 Nov").isToday(noon, calendar: calendar))
  print("Decoding: real ready and scheduled rows, extra backend keys, cues, malformed sources and every status's wording.")

  let store = Store()
  var playable = afternoon
  playable.audio_url = "https://fixture.invalid/api/day_episodes/audio/afternoon-id.m4a?token=fixture"
  store.service.value = DayEpisodes(day: decoded.day, timezone: decoded.timezone, episodes: [playable, evening])
  await store.refreshDayEpisodes()
  precondition(store.dayEpisodes == [playable, evening] && !store.dayEpisodesRefreshing && store.service.calls == 1)
  precondition(store.reader.current == nil)
  store.service.value = nil; await store.refreshDayEpisodes(); precondition(store.dayEpisodes == [playable, evening])
  store.toggleDayEpisode(evening); precondition(store.reader.current == nil)
  store.toggleDayEpisode(playable)
  precondition(store.playingDayEpisodeID == "afternoon-id" && store.currentDayEpisodeID == "afternoon-id")
  precondition(store.reader.current?.stableID == "day:afternoon-id" && store.reader.current?.kind == "note")
  precondition(store.reader.current?.speechChunks.map(\\.url.absoluteString) == [playable.audio_url])
  precondition(!store.showBriefingStage, "The morning's room stays the morning's")
  store.toggleDayEpisode(playable); precondition(store.playingDayEpisodeID == nil && store.currentDayEpisodeID == "afternoon-id")
  let item = Playlist.Item(id: playable.id, kind: "note", title: playable.title, body: playable.text, source: "alicia_day_episode",
                           duration: playable.duration, speechChunks: [SpeechChunk(url: URL(string: playable.audio_url)!, duration: playable.duration)])
  precondition(item.readable.id == store.reader.current?.id && item.readable == store.reader.current)
  store.readAloud(item.readable); precondition(store.playingDayEpisodeID == "afternoon-id")
  var timed = playable
  timed.speechChunks = [SpeechChunk(url: URL(string: "https://fixture.invalid/api/reading/c0.m4a")!, duration: 13.9, text: "What")]
  let fresh = Store(); fresh.toggleDayEpisode(timed)
  precondition(fresh.reader.current?.speechChunks == timed.speechChunks)
  let morning = Playlist.Item(id: "m", kind: "note", title: "Morning", body: "Text", source: "alicia_morning_briefing", duration: 9, speechChunks: [])
  fresh.readAloud(morning.readable); precondition(fresh.currentDayEpisodeID == nil && fresh.playingDayEpisodeID == nil)
  fresh.acceptDayEpisodes(DayEpisodes()); precondition(fresh.dayEpisodes.isEmpty)
  print("Store: read-only refresh, nil retention, not-ready no-op, play and pause, one reading with the Studio item, cached chunks first, no briefing room.")
 }
}
'''

with tempfile.TemporaryDirectory(prefix='day-episodes-home-') as directory:
    source = Path(directory) / 'check.swift'
    binary = Path(directory) / 'check'
    source.write_text(program)
    subprocess.run(['swiftc', '-parse-as-library', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('day episodes on Us: all checks passed')
