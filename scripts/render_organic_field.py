#!/usr/bin/env python3
"""Render the briefing room's field, as shipped and organic, side by side (CL-20261018-organic-field).

An offline render of the app's own math. It compiles PresenceGeometry.swift and
OrganicField.swift, the same files the app draws from, and draws each frame
with CoreGraphics:
- the room's paper and morning tint;
- her body at 1.45× the screen and 0.72 opacity, as the room places it;
- her real speaking rhythm (scripts/fixtures/organic_voice_timing.json, word
  times only).

Left: TestFlight 49. The walk's listening pose, at 15 frames a second, with the
per-word level polled every 66 ms. Right: the organic candidate with every
toggle on, at 30 frames a second, with Higher at 12 s and Lower at 24 s.

Not drawn: the paper grain, and SwiftUI's own antialiasing. Judging on the
simulator, and then the phone, remains the Motion Lab's job.

Usage: render_organic_field.py OUTPUT_DIR [--seconds 36]
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]).resolve()
seconds = float(sys.argv[sys.argv.index('--seconds') + 1]) if '--seconds' in sys.argv else 36.0
timing = json.loads((root / 'scripts/fixtures/organic_voice_timing.json').read_text())
cues = ', '.join('(%r, %r)' % (s, e) for s, e in timing['cues'])

renderer = r'''
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let words: [(Double, Double)] = [CUES]
let loop = LOOP
let seconds = SECONDS
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let pane = CGSize(width: 402, height: 874)       // an iPhone 17 screen, in points
let scale: CGFloat = 1.5
let labelHeight: CGFloat = 34
let cues: [OrganicVoice.Cue] = (0..<4).flatMap { k in words.map { OrganicVoice.Cue(start: $0.0 + Double(k) * loop, end: $0.1 + Double(k) * loop) } }

// TestFlight 49's driver: BriefingPlanner.voiceLevel at 71ce1d8, polled every 66 ms.
func shippedLevel(_ t: Double) -> Double {
    var level = 0.08
    for cue in cues {
        if t < cue.start { break }
        if t < cue.end { return 0.45 + 0.55 * sin(.pi * min(1, (t - cue.start) / max(0.05, cue.end - cue.start))) }
        level = max(0.08, 0.45 * exp(-(t - cue.end) / 0.12))
    }
    return min(1, max(0, level))
}
func phase(_ t: Double, energy: Double) -> Double { 2.0 + t * (.pi / 4) * (0.45 + energy * 1.1) }

func shippedFrame(_ t: Double) -> PresenceFrame {
    // 15 frames a second, and a level up to 66 ms stale.
    let frameTime = (t * 15).rounded(.down) / 15
    let polled = (frameTime / 0.066).rounded(.down) * 0.066
    return PresenceFrame(primary: PresenceForm.knot.rawValue, secondary: PresenceForm.drift.rawValue, mix: 0.4,
                         phase: phase(frameTime, energy: 0.62), energy: 0.62, openness: 1, coherence: 0.9,
                         focus: CGPoint(x: 0.5, y: 0.44), listening: true, level: shippedLevel(polled))
}
func gestureAt(_ t: Double) -> Double {
    for (start, sign) in [(12.0, 1.0), (24.0, -1.0)] {
        let p = (t - start) / 1.4
        if p >= 0 && p <= 1 { let b = sin(.pi * p); return sign * b * b }
    }
    return 0
}
func organicFrame(_ t: Double) -> PresenceFrame {
    var f = PresenceFrame(primary: PresenceForm.drift.rawValue, secondary: PresenceForm.knot.rawValue, mix: 0.15,
                          phase: phase(t, energy: 0.56), energy: 0.56, openness: 0.72, coherence: 0.84,
                          focus: CGPoint(x: 0.5, y: 0.42))
    let near = OrganicVoice.window(cues, around: t)
    f.speaking = true
    f.word = OrganicVoice.word(near, at: t)
    f.phraseTrail = OrganicVoice.trail(near, at: t)
    f.gesture = gestureAt(t)
    return f
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ink = (0.165, 0.153, 0.137)
func background(_ ctx: CGContext, _ rect: CGRect) {
    let paper = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.953, green: 0.933, blue: 0.890, alpha: 1),
        CGColor(red: 0.914, green: 0.886, blue: 0.831, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.minX, y: rect.minY), options: [])
    let tint = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.95, green: 0.80, blue: 0.45, alpha: 0.30),
        CGColor(red: 0.95, green: 0.88, blue: 0.66, alpha: 0.08)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(tint, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.minX, y: rect.minY), options: [])
}
func label(_ ctx: CGContext, _ text: String, at point: CGPoint, size: CGFloat, alpha: CGFloat = 0.8) {
    let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: ink.0, green: ink.1, blue: ink.2, alpha: alpha),
        NSAttributedString.Key(kCTKernAttributeName as String): 1.6]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    ctx.textPosition = point
    CTLineDraw(line, ctx)
}
// Draws a field into a pane whose top-left is `origin` (in flipped, top-down points).
func drawPane(_ ctx: CGContext, origin: CGPoint, frame: PresenceFrame, organic: Bool) {
    let rect = CGRect(origin: origin, size: pane)
    ctx.saveGState()
    ctx.clip(to: rect)
    background(ctx, rect)
    let field = CGSize(width: pane.width * 1.45, height: pane.height * 1.45)
    let offset = CGPoint(x: origin.x + (pane.width - field.width) / 2, y: origin.y + (pane.height - field.height) / 2)
    func color(_ a: Double) -> CGColor { CGColor(red: ink.0, green: ink.1, blue: ink.2, alpha: CGFloat(a * 0.72)) }
    if organic {
        let placed = OrganicField.points(frame: frame, size: field, style: .all, source: PresenceGeometry.sourcePoint)
        for layer in 0..<3 {
            ctx.setFillColor(color(placed.opacities[layer]))
            for dot in placed.dots where dot.layer == layer {
                ctx.fillEllipse(in: CGRect(x: offset.x + dot.point.x - dot.size / 2, y: offset.y + dot.point.y - dot.size / 2, width: dot.size, height: dot.size))
            }
        }
        ctx.setFillColor(color(placed.dustOpacity))
        for dot in placed.dust {
            ctx.fillEllipse(in: CGRect(x: offset.x + dot.point.x - dot.size / 2, y: offset.y + dot.point.y - dot.size / 2, width: dot.size, height: dot.size))
        }
    } else {
        let placed = PresenceGeometry.currentPoints(frame: frame, size: field)
        ctx.setFillColor(color(placed.opacity))
        for p in placed.points { ctx.fill(CGRect(x: offset.x + p.x, y: offset.y + p.y, width: placed.dot, height: placed.dot)) }
    }
    ctx.restoreGState()
}

let width = Int((pane.width * 2 + 12) * scale), height = Int((pane.height + labelHeight) * scale)
let fps = 30.0
let total = Int(seconds * fps)
var spoken = 0.0
for i in 0..<total {
    let t = Double(i) / fps
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }
    ctx.setFillColor(CGColor(red: 0.953, green: 0.933, blue: 0.890, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // Flip to top-down points.
    ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: scale, y: -scale)
    ctx.setShouldAntialias(true)
    drawPane(ctx, origin: CGPoint(x: 0, y: labelHeight), frame: shippedFrame(t), organic: false)
    drawPane(ctx, origin: CGPoint(x: pane.width + 12, y: labelHeight), frame: organicFrame(t), organic: true)
    // Labels in bottom-up text space.
    ctx.saveGState(); ctx.scaleBy(x: 1, y: -1)
    label(ctx, "AS SHIPPED · TESTFLIGHT 49 · 15 FPS", at: CGPoint(x: 10, y: -22), size: 9)
    label(ctx, "ORGANIC · LAB CANDIDATE · 30 FPS", at: CGPoint(x: pane.width + 22, y: -22), size: 9)
    let g = gestureAt(t)
    if g != 0 { label(ctx, g > 0 ? "HIGHER" : "LOWER", at: CGPoint(x: pane.width * 1.5 - 18, y: -(pane.height + labelHeight - 30)), size: 11, alpha: CGFloat(0.4 + 0.5 * abs(g))) }
    let near = OrganicVoice.window(cues, around: t)
    let speakingNow = OrganicVoice.word(near, at: t) > 0.3
    if speakingNow { spoken += 1 }
    label(ctx, String(format: "%04.1fs  %@", t, speakingNow ? "HER VOICE" : "·"), at: CGPoint(x: 10, y: -(pane.height + labelHeight - 14)), size: 8, alpha: 0.55)
    ctx.restoreGState()
    let image = ctx.makeImage()!
    let url = outDir.appendingPathComponent(String(format: "frame_%05d.png", i))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
print("rendered \(total) frames, \(width)x\(height)")
'''.replace('CUES', cues).replace('LOOP', repr(float(timing.get('loop_seconds', 36.6)))).replace('SECONDS', repr(seconds))

out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as d:
    frames = Path(d) / 'frames'
    frames.mkdir()
    (Path(d) / 'main.swift').write_text(renderer)
    swiftc = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
    sdk = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
    subprocess.run([swiftc, '-O', '-sdk', sdk, '-module-cache-path', d + '/mc',
                    str(root / 'Alicia/DesignSystem/PresenceGeometry.swift'),
                    str(root / 'Alicia/DesignSystem/OrganicField.swift'), d + '/main.swift', '-o', d + '/render'],
                   check=True, env=dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'))
    subprocess.run([d + '/render', str(frames)], check=True)
    video = out / 'organic-vs-shipped.mp4'
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', '30', '-i', str(frames / 'frame_%05d.png'),
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-movflags', '+faststart', str(video)], check=True)
    for name, second in (('mid-phrase', 8.0), ('pause', 5.9), ('higher', 12.7), ('lower', 24.7)):
        index = int(second * 30)
        source = frames / ('frame_%05d.png' % index)
        if source.exists():
            (out / ('still-%s.png' % name)).write_bytes(source.read_bytes())
    print('wrote', video)
