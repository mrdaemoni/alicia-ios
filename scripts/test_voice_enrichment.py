#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'Alicia/Core/VoiceEnrichment.swift').read_text()+'''
let json = #"{"analysis_state":"ready","analysis_id":"analysis-v1","insights":[{"id":"insight-1","text":"A tentative connection","evidence":[{"source":"audio","ref":"part-1","quote":"enough","start":12.5,"end":13.1}],"goal_ids":["goal-1"]}],"coverage":{"recorded_seconds":276.6,"covered_seconds":276.6,"tail_covered":true},"pass_receipts":[{"pass":"fidelity","provider":"gemini","model":"actual-receipt","status":"ready"}]}"#
let projection = try JSONDecoder().decode(VoiceEnrichment.self,from:Data(json.utf8))
precondition(projection.insights?.first?.evidence?.first?.start == 12.5)
precondition(projection.coverage?.tail_covered == true)
precondition(projection.pass_receipts?.first?.model == "actual-receipt")
let references=try JSONDecoder().decode(VoiceEnrichment.Answer.self,from:Data(#"{"id":"candidate-1","text":"Possible answer","goal_id":"goal-1","evidence":["insight-1",{"quote":"enough","source":"fidelity"}]}"#.utf8))
precondition(references.evidence?.count == 2)
let minimal=try JSONDecoder().decode(VoiceEnrichment.self,from:Data(#"{"analysis_state":"none"}"#.utf8))
precondition(minimal.insights == nil)
let original=VoiceEnrichmentFeedback(recording_id:"fixture-recording",analysis_id:"analysis-v1",item_id:"insight-1",verdict:"clarify",text:"These are Hector's exact words.")
let saved=try JSONEncoder().encode(original)
let restored=try JSONDecoder().decode(VoiceEnrichmentFeedback.self,from:saved)
precondition(restored.request_id == original.request_id && restored.text == original.text)
precondition(restored.body["analysis_id"] as? String == "analysis-v1")
precondition(restored.body["item_id"] as? String == "insight-1")
precondition(restored.body["action"] as? String == "enrichment_feedback")
print("9 enrichment contract and immutable retry checks passed")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'test.swift';p.write_text(source)
 subprocess.run(['swiftc',str(p),'-o',d+'/checks'],check=True)
 subprocess.run([d+'/checks'],check=True)
