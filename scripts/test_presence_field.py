#!/usr/bin/env python3
"""Hermetic check: transport timestamps never restart Alicia's presence field."""

from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Alicia" / "Core" / "PresenceField.swift"


def extract_struct(text: str, name: str) -> str:
    start = text.index(f"struct {name}")
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise AssertionError(f"unterminated {name}")


body = extract_struct(SOURCE.read_text(), "PresenceAwareness")
harness = body + r'''

@main
struct Checks {
    static func main() {
        let first = PresenceAwareness(
            energy: 0.4, openness: 0.6, coherence: 0.75,
            direction: "inward", stance: "witness",
            attending_to: "Holding what we're working toward",
            source: "local", updated_at: "2026-09-26T10:00:00Z")
        let timestampOnly = PresenceAwareness(
            energy: 0.4, openness: 0.6, coherence: 0.75,
            direction: "inward", stance: "witness",
            attending_to: "Holding what we're working toward",
            source: "local", updated_at: "2026-09-26T10:01:00Z")
        precondition(first == timestampOnly, "timestamp-only polls must compare equal")

        var changed = timestampOnly
        changed.energy = 0.6
        precondition(first != changed, "motion-driving changes must compare unequal")
        print("presence field equality checks passed")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alicia-presence-field-") as temp:
    source = Path(temp) / "Checks.swift"
    binary = Path(temp) / "checks"
    source.write_text(harness)
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
