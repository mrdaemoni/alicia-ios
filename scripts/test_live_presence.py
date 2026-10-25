#!/usr/bin/env python3
"""Compile actual value types/equations; no service, credentials, or device I/O."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
models = (root/'Alicia/Core/LivePresence.swift').read_text().split('/// Live presence.')[0]
models = models.removeprefix('#if DEBUG\n').replace('import Observation', '')
geometry = (root/'Alicia/DesignSystem/RelationalGeometry.swift').read_text().removeprefix('#if DEBUG\n').removesuffix('#endif\n')
harness = r'''
@main struct Checks {
 static func main() throws {
  precondition(PresencePlaybackPolicy.shared(kind: "note", stableID: "morning:fixture"))
  precondition(!PresencePlaybackPolicy.shared(kind: "note", stableID: nil))
  precondition(!PresencePlaybackPolicy.shared(kind: "body", stableID: "morning:fixture"))
  var fact = LivePresenceFact()
  fact.activity = "listening"; fact.remainingMS = 2000; fact.level = 0.7
  precondition(fact.fresh(after: 1.999).activity == "listening")
  precondition(fact.fresh(after: 2).activity == "unavailable")
  precondition(fact.fresh(after: 4).level == 0)
  var motion = RelationalMotion(now: 0)
  motion.update(fact, now: 0)
  let before = motion.frame(now: 0.6)
  fact.activity = "thinking"; fact.expression.stance = "ask"
  motion.update(fact, now: 0.6)
  let after = motion.frame(now: 0.6)
  precondition(before.phases == after.phases && before.parameters == after.parameters, "retarget must be continuous")
  let still = motion.frame(now: 1, reduced: true)
  precondition(still.phases == motion.frame(now: 100, reduced: true).phases && still.parameters.level == 0)
  for stance in ["witness", "ask", "offer", "celebrate", "hold", "challenge"] {
   for activity in ["listening", "thinking", "speaking", "resting", "unavailable"] {
    fact.expression.stance = stance; fact.activity = activity
    motion.update(fact, now: 10)
    for t in [10.0, 10.01, 10.5, 12, 25] {
     let points = RelationalGeometry.positions(motion.frame(now: t), size: CGSize(width: 390, height: 844))
     precondition(!points.isEmpty && points.count <= 2400)
     precondition(points.allSatisfy { $0.0.x.isFinite && $0.0.y.isFinite })
    }
   }
  }
  let url = URL(fileURLWithPath: CommandLine.arguments[1])
  let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
  for row in fixtures {
   let f = row["family"] as! Int, i = row["index"] as! Int, t = row["phase"] as! Double
   let sample = RelationalGeometry.sample(f, i), expected = row["point"] as! [Double]
   let p = RelationalGeometry.point(f, sample, t)
   precondition(sample == row["sample"] as! Double)
   precondition(abs(p.x-expected[0]) < 1e-7 && abs(p.y-expected[1]) < 1e-7, "room/phone equation mismatch")
  }
  print("live presence: expiry, continuous morph, stillness, finite budget, shared equations passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='live-presence-check-') as temp:
    src=Path(temp)/'Checks.swift'; binary=Path(temp)/'checks'
    src.write_text(models+geometry+harness)
    subprocess.run(['xcrun','swiftc','-parse-as-library',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary),str(root/'docs/live-presence-equations.json')],check=True)
