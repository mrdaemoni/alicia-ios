#!/usr/bin/env python3
"""Check the organic field candidate's pure math (CL-20261018-organic-field).

Compiles Alicia/DesignSystem/PresenceGeometry.swift and OrganicField.swift with
swiftc for the Mac and runs Foundation-only checks:
- with every toggle off, the candidate places exactly the shipped field's points;
- every form, pose, phrase and gesture is finite and visible;
- the breath is bounded, the voice envelopes are smooth and stateless, and the
  gestures move her the way their names say;
- a frame is a pure function of its inputs;
- per-frame placement cost, measured on this Mac. A phone needs its own
  measurement.

Her rhythm comes from scripts/fixtures/organic_voice_timing.json: word times
only, no text.
"""
from pathlib import Path
import json
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
timing = json.loads((root / 'scripts/fixtures/organic_voice_timing.json').read_text())
cues = ', '.join('(%r, %r)' % (s, e) for s, e in timing['cues'])

checks = r'''
import Foundation
var passed = 0
setvbuf(stdout, nil, _IOLBF, 0)
func check(_ ok: Bool, _ message: @autoclosure () -> String) {
    guard ok else { print("FAILED: " + message()); exit(1) }
    passed += 1
}
let words: [(Double, Double)] = [CUES]
let cues = words.map { OrganicVoice.Cue(start: $0.0, end: $0.1) }
let size = CGSize(width: 402 * 1.45, height: 874 * 1.45)

func frame(_ primary: Int, _ secondary: Int, phase: Double, listening: Bool = false, speaking: Bool = false,
           level: Double = 0, word: Double = 0, phrase: Double = 0, gesture: Double = 0) -> PresenceFrame {
    var f = PresenceFrame(primary: primary, secondary: secondary, mix: 0.3, phase: phase, energy: 0.56,
                          openness: 0.72, coherence: 0.84, focus: CGPoint(x: 0.5, y: 0.42), listening: listening,
                          level: level)
    f.speaking = speaking; f.word = word; f.phraseTrail = Array(repeating: phrase, count: 8); f.gesture = gesture
    return f
}
func place(_ f: PresenceFrame, _ style: OrganicStyle) -> OrganicField.Placed {
    OrganicField.points(frame: f, size: size, style: style, source: PresenceGeometry.sourcePoint)
}

// 1. Every toggle off is the field as it ships: the same points, in order.
for (p, s) in [(5, 0), (0, 5), (2, 4)] {
    for phase in [0.0, 2.3, 4.6] {
        for level in [0.0, 0.7] {
            let f = frame(p, s, phase: phase, listening: true, level: level)
            let shipped = PresenceGeometry.currentPoints(frame: f, size: size)
            let candidate = place(f, .shipped)
            check(candidate.dots.map(\.point) == shipped.points && candidate.dots.allSatisfy { $0.size == shipped.dot }
                  && candidate.dust.isEmpty && candidate.opacities.allSatisfy { $0 == shipped.opacity },
                  "Toggles off reproduce the shipped field (forms \(p)/\(s), phase \(phase), level \(level))")
        }
    }
}

// 2. Finite and visible for every form pair, pose, voice and gesture.
var lowest = 1.0, frames = 0
for p in PresenceForm.allCases.indices {
    for s in PresenceForm.allCases.indices {
        for (listening, speaking) in [(false, true), (true, false), (false, false)] {
            for phase in [0.0, 1.7, 3.4, 5.1] {
                for v in [0.0, 1.0] {
                    let placed = place(frame(p, s, phase: phase, listening: listening, speaking: speaking,
                                             level: v, word: v, phrase: v, gesture: v == 1 ? 1 : -1), .all)
                    frames += 1
                    check(placed.dots.allSatisfy { $0.point.x.isFinite && $0.point.y.isFinite && $0.size > 0 }, "finite dots")
                    let total = Double(min(3_000, max(950, Int((Double(PresenceForm.allCases[p].basePoints) * 0.7
                        + Double(PresenceForm.allCases[s].basePoints) * 0.3) * (0.92 + 0.56 * 0.55)))))
                    lowest = min(lowest, Double(placed.dots.count) / total)
                }
            }
        }
    }
}
check(lowest >= 0.35, "Every form, pose and voice keeps at least 35% of her visible (lowest \(Int(lowest * 100))%)")
print("audit: \(frames) frames, lowest visible \(Int(lowest * 100))%")

// 3. The phrase breathes at most 4.5%: a gentle breath, not a speaker cone.
do {
    var calm = OrganicStyle.all; calm.particleLife = false; calm.roomFraming = false
    let quiet = place(frame(0, 5, phase: 2, speaking: true, phrase: 0), calm)
    let full = place(frame(0, 5, phase: 2, speaking: true, phrase: 1), calm)
    let centre = CGPoint(x: size.width / 2, y: size.height / 2)
    func spread(_ p: OrganicField.Placed) -> Double {
        p.dots.map { Double(hypot($0.point.x - centre.x, $0.point.y - centre.y)) }.reduce(0, +) / Double(p.dots.count)
    }
    let ratio = spread(full) / spread(quiet)
    check(ratio > 1.0 && ratio < 1.05, "A full phrase widens her by under 5% (\(String(format: "%.3f", ratio)))")
    var cone = OrganicStyle.shipped
    let pumped = spread(place(frame(0, 5, phase: 2, listening: true, level: 1), cone)) /
        spread(place(frame(0, 5, phase: 2, listening: true, level: 0), cone))
    cone.twoTimescales = true
    check(pumped > 1.15, "The shipped field pumps her over 15% per word (\(String(format: "%.3f", pumped)))")
}

// 4. Her voice on two timescales: stateless, smooth, and the phrase slower than the word.
do {
    let first = cues[0]
    let rise = OrganicVoice.word(cues[...], at: first.start + OrganicVoice.attack)
    check(abs(rise - (1 - exp(-1))) < 0.01, "A word reaches 63% after its 60 ms attack")
    let held = OrganicVoice.word(cues[0..<1], at: first.end)
    let after = OrganicVoice.word(cues[0..<1], at: first.end + OrganicVoice.release)
    check(abs(after / held - exp(-1)) < 0.01, "A word falls to 37% one 400 ms release after it ends")
    // The phrase should rise and fall once per phrase, never jitter per word:
    // count direction reversals (beyond a small dead zone) of each signal.
    var wordTurns = 0, phraseTurns = 0, worstStep = 0.0
    var previousWord = 0.0, previousPhrase = 0.0, wordTrend = 0.0, phraseTrend = 0.0
    var t = 0.0
    while t < 36.3 {
        let near = OrganicVoice.window(cues, around: t)
        let w = OrganicVoice.word(near, at: t), p = OrganicVoice.phrase(near, at: t)
        if t > 0 {
            worstStep = max(worstStep, abs(p - previousPhrase))
            let dw = w - previousWord, dp = p - previousPhrase
            if abs(dw) > 0.002 { if dw * wordTrend < 0 { wordTurns += 1 }; wordTrend = dw }
            if abs(dp) > 0.002 { if dp * phraseTrend < 0 { phraseTurns += 1 }; phraseTrend = dp }
        }
        check(w == OrganicVoice.word(cues[...], at: t) && p == OrganicVoice.phrase(cues[...], at: t),
              "The window gives the same voice as every cue at \(t)")
        previousWord = w; previousPhrase = p
        t += 1.0 / 60
    }
    print("over 36 s of her speech: word turns \(wordTurns), phrase turns \(phraseTurns)")
    check(phraseTurns * 3 < wordTurns, "The phrase turns far less often than the words (\(phraseTurns) vs \(wordTurns))")
    check(worstStep < 0.03, "The phrase never jumps between 60 Hz frames (largest step \(String(format: "%.3f", worstStep)))")
    let gap = cues.indices.dropLast().max { cues[$0 + 1].start - cues[$0].end < cues[$1 + 1].start - cues[$1].end }!
    let settled = OrganicVoice.phrase(cues[...], at: cues[gap + 1].start - 0.05)
    let speaking = OrganicVoice.phrase(cues[...], at: cues[gap].end)
    check(settled < speaking * 0.5, "In the longest pause the phrase settles to under half (\(String(format: "%.2f → %.2f", speaking, settled)))")
}

// 5. Gestures do what their names say.
do {
    func centroid(_ p: OrganicField.Placed) -> (y: Double, r: Double) {
        let n = Double(p.dots.count)
        let cx = p.dots.map { Double($0.point.x) }.reduce(0, +) / n, cy = p.dots.map { Double($0.point.y) }.reduce(0, +) / n
        return (cy, p.dots.map { hypot(Double($0.point.x) - cx, Double($0.point.y) - cy) }.reduce(0, +) / n)
    }
    var still = OrganicStyle.all; still.particleLife = false; still.roomFraming = false
    let rest = centroid(place(frame(0, 5, phase: 2, speaking: true), still))
    let higher = centroid(place(frame(0, 5, phase: 2, speaking: true, gesture: 1), still))
    let lower = centroid(place(frame(0, 5, phase: 2, speaking: true, gesture: -1), still))
    check(higher.y < rest.y && higher.r < rest.r, "Higher gathers and lifts her")
    check(lower.y > rest.y && lower.r > rest.r, "Lower opens and settles her")
}

// 6. A frame is a pure function: the same inputs give the same particles.
do {
    let f = frame(3, 1, phase: 4.2, speaking: true, word: 0.4, phrase: 0.6)
    let a = place(f, .all), b = place(f, .all)
    check(a.dots.map(\.point) == b.dots.map(\.point) && a.dust.map(\.point) == b.dust.map(\.point), "Deterministic")
}

// 7. What a frame costs to place on this Mac (a phone must be measured on the phone).
func cost(_ style: OrganicStyle, shipped: Bool) -> Double {
    let start = Date()
    for i in 0..<120 {
        let f = frame(0, 5, phase: Double(i) / 30, listening: shipped, speaking: !shipped, level: 0.5, word: 0.5, phrase: 0.5)
        if shipped { _ = PresenceGeometry.currentPoints(frame: f, size: size) } else { _ = place(f, style) }
    }
    return Date().timeIntervalSince(start) / 120 * 1000
}
let shippedMs = cost(.shipped, shipped: true), organicMs = cost(.all, shipped: false)
print(String(format: "placement per frame on this Mac: shipped %.2f ms, organic %.2f ms", shippedMs, organicMs))
check(organicMs < 8, "Organic placement stays under 8 ms a frame here (\(String(format: "%.2f", organicMs)) ms)")
print("\(passed) organic field checks passed")
'''.replace('CUES', cues)

with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as d:
    main = Path(d) / 'main.swift'
    main.write_text(checks)
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    swiftc = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
    sdk = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
    subprocess.run([swiftc, '-O', '-sdk', sdk, '-module-cache-path', d + '/mc',
                    str(root / 'Alicia/DesignSystem/PresenceGeometry.swift'),
                    str(root / 'Alicia/DesignSystem/OrganicField.swift'), str(main), '-o', d + '/checks'],
                   check=True, env=env)
    subprocess.run([d + '/checks'], check=True)
