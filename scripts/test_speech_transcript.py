#!/usr/bin/env python3
"""Exercise retained long-form hypotheses from the actual Swift buffer."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='alicia-speech-buffer-') as temporary:
    folder = Path(temporary)
    main = folder / 'main.swift'
    main.write_text(r'''
import Foundation
typealias Word = SpeechTranscriptBuffer.Word
var count = 0
func check(_ ok: Bool, _ description: String) {
    guard ok else { fatalError(description) }
    count += 1
}
func word(_ text: String, _ start: Double) -> Word { Word(text: text, start: start, duration: 0.3) }
var buffer = SpeechTranscriptBuffer()
buffer.receive([word("Pruning", 1), word("versus", 1.5), word("shrinking", 2)])
buffer.receive([word("Pruning", 1), word("and", 1.5), word("shrinking", 2)])
check(buffer.text == "Pruning and shrinking", "Current hypothesis must remain correctable")
buffer.receive([word("A", 65), word("different", 65.5), word("altitude", 66)])
check(buffer.text == "Pruning and shrinking A different altitude", "A later utterance must not erase the earlier minute")
buffer.receive([])
check(buffer.text.contains("Pruning"), "Empty partial must preserve prior capture")
buffer.receive([word("altitude", 0)])
check(buffer.needsReview && buffer.text.contains("Pruning"), "Regressed timing must be visible and preserve captured words")
buffer.finishRequest()
buffer.receive([word("Enough", 0), word("before", 0.5), word("and", 1), word("after", 1.5)])
check(buffer.text.contains("altitude\n\nEnough"), "Request rollover must preserve preceding capture")
buffer.finishRequest()
let complete = buffer.text
buffer.finishRequest()
check(buffer.text == complete, "Repeated finish must not duplicate committed words")
var long = SpeechTranscriptBuffer()
for minute in 0..<6 {
    for sentence in 0..<6 {
        long.receive([word("minute\(minute)-sentence\(sentence)", Double(sentence * 9))])
    }
    long.finishRequest()
}
check(long.text.contains("minute0-sentence0") && long.text.contains("minute5-sentence5"), "Retain beginning and ending of several-minute recording")
check(long.text.split(whereSeparator: \.isWhitespace).count == 36, "Every timed sentence appears once")
var invalid = SpeechTranscriptBuffer()
invalid.receive([word("kept", 0)])
invalid.receive([Word(text:"bad",start:.nan,duration:1)])
check(invalid.needsReview && invalid.text == "kept", "Reject invalid timestamps without erasing words")
print("\(count) speech transcript checks passed")
''')
    binary = folder / 'test'
    subprocess.run(['xcrun', 'swiftc', str(root / 'Alicia/Core/SpeechTranscriptBuffer.swift'), str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
