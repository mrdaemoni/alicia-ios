#!/usr/bin/env python3
"""Actual BodyCapture sort versus the exact build-45 parser; synthetic events."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
old = subprocess.check_output(['git', 'show', '0720005:Shared/BodyCapture.swift'], cwd=root, text=True)
start = old.index('    static func instant(')
end = old.index('    static func root()', start)
reference = old[start:end]
program = r'''
import Foundation
enum Build45 {
__REFERENCE__
}
@main struct Checks {
 static func main() {
  let samples = ["2026-10-12T22:00:00.123Z", "2026-10-12T22:00:00Z", "2026-10-13T00:00:00+02:00", "invalid"]
  for value in samples {precondition(BodyCapture.instant(value) == Build45.instant(value))}
  var events:[BodyEvent] = []
  for index in 0..<180 {
   var event = BodyEvent(kind:"ritual",now:Date(timeIntervalSince1970:1_790_000_000+Double((index*37)%180)))
   event.request_id = String(format:"inert-%06d", index)
   events.append(event)
  }
  let start = Date()
  let reference = events.sorted(by:Build45.before)
  let oldTime = Date().timeIntervalSince(start)
  let next = Date()
  for _ in 0..<30 {precondition(BodyCapture.sorted(events).map(\.id) == reference.map(\.id))}
  let newTime = Date().timeIntervalSince(next)/30
  precondition(newTime < oldTime/5, "sort still recreates formatters at comparison cost")
  // A larger archive must remain far below the phone's 10-second watchdog.
  let larger = Array(repeating:events,count:12).flatMap{$0}
  let largeStart = Date()
  for _ in 0..<10 {_ = BodyCapture.sorted(larger)}
  let largeTime = Date().timeIntervalSince(largeStart)/10
  precondition(largeTime < 0.5)
  print(String(format:"Body sort passed: build45 %.4fs, candidate %.6fs per sort; 2160-event sort %.6fs. Ordering/timezone/invalid-date behavior unchanged.",oldTime,newTime,largeTime))
 }
}
'''.replace('__REFERENCE__', reference)
with tempfile.TemporaryDirectory(prefix='alicia-body-sort-') as directory:
    directory = Path(directory)
    source = directory/'checks.swift'; source.write_text(program)
    binary = directory/'checks'
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['xcrun','swiftc','-O','-parse-as-library',str(root/'Shared/BodyCapture.swift'),str(source),'-o',str(binary)], check=True, env=env)
    subprocess.run([str(binary)], check=True, env=env, timeout=25)
