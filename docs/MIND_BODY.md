# A clear mind and a healthy body — A2-043 candidate

Hector's September 13 direction makes these Alicia's two ultimate outcomes.
The product has five tabs: **Us, Mind, Body, Alicia, Studio**. This document describes an unreleased candidate, not a deployment or TestFlight receipt.

## The phone

Us retains the morning briefing, current episode and Together work. A mind/body overview shows shared and wellness goals, dated Oura observations and recorded rituals. An invitation connects the current episode or a selected shared goal to Hector's energy and attention. Fits / Not sure / Doesn't fit and optional words create a private reflection with the exact displayed prompt, episode ID and selected goal IDs. This is a question to explore, not an inferred causal relationship or a model-authored insight.

Mind contains Knowledge and Thinkers. Alicia keeps its existing current reading, thoughts and archetype traces. Studio remains the artifact library, morning playlist and immersive natural reader; its Canvas/Draw switch is retired. Existing drawing files and APIs are retained, not erased. Dialogue remains a shared one-tap action; it no longer occupies a tab. Internal AppSection.mind remains the Alicia section and .knowledge is labelled Mind, preserving existing routes. AppSection.tabs alone defines the five visible tabs.

Body has Today, Goals and Evidence. Today offers exercise, cold plunge and sauna capture plus four dated Oura metrics and their available histories/baselines. Missing measurements are unknown, never zero or a substituted average. Goals have an explicit intention, progress criterion, optional metric and historical source IDs. There is no three-goal cap. Review/edit can pause, archive or explicitly confirm achievement; previous versions survive. Evidence opens paged exact local report excerpts and source receipts. Dates unavailable in the source contract stay unknown.

An optional private question uses the existing guarded local model transport. It gets latest wellness goals, current available daily measurements, the last ten explicit private ritual/reflection inputs and the requested historical retrieval. Oversized or stale packets fail explicitly, with no cloud fallback. It does not save the exchange, infer agreement, diagnose or train. Local model answer quality remains a separate field check. Private narration is unavailable; the cloud reader is never invoked from Body.

## Durable rituals and boundaries

The medium-size **Daily rituals** WidgetKit widget has a direct AppIntent for each ritual. A tap means explicitly recorded completion at the tap's time/day/timezone. The widget saves an immutable UUID file into the existing app group, outside iCloud backup, and shows pending sync. It does not store clinical metrics or credentials. The app syncs when opened/foregrounded or refreshed; unattended background upload is not promised. An explicit midnight timeline entry starts a fresh local day. Repeated taps set completion rather than toggle it; Undo in Body records a new correction. Missing capture does not prove absence.

Shared/BodyCapture.swift is compiled into both app and widget targets. Separate atomic event and acknowledgement files avoid a cross-process read-modify-write race. Saves/retries keep the same payload. A successful server receipt is distinct from local retention. A known rejected edit can be explicitly discarded without deleting its original file; unknown network outcomes retain their retry. Mock/preview mode never writes personal captures.

## Backend and privacy

All routes require the existing iOS token. GET /api/body projects private state and current read-only bridge evidence. POST /api/body records a typed explicit event. GET /api/body/source?id=...&offset=...&sha256=... reads five exact indexed passages per page by catalog ID, never an arbitrary path. A provided source fingerprint must still match before excerpts are returned. POST /api/body/ask requests optional local inference. JSON is no-store and the phone uses an ephemeral session that refuses redirects for these routes. Temporary evidence/state failures return503 and preserve retry; invalid or conflicting input returns409. Local inference has a longer request timeout than ordinary status refreshes.

BodyJournalV1 / BodyEventV1 and body_journal.json are registered in schemas, bridge_schema and contract_registry. health_context.record_body_event serializes writes under a separate stable lock using safe_io.atomic_write_json. Duplicate receipts return the same acknowledgement; changed receipts and stale goal revisions fail. Corrupt state is not replaced. Private state is at /Users/alicia/Documents/health/alicia_private/body_journal.json, outside the vault and general memory. Schema error formatting hides input values. Historical HealthBridge files are strictly read-only.

The health bridge is refreshed by its existing owner. This feature does not add an Oura fetch job or credentials. Stale/unavailable evidence is visible while authored goals remain available. These private goals/reflections do not enter existing cloud Opus projects, Telegram, general conversation history, narration, training or the morning generation packet. Existing mind goals continue unchanged. No new scheduler, proactive send or learning loop is introduced.

## Verification and delivery

Run tests/test_body_context.py, existing health tests, smoke, contracts, docs_drift, diff-check and deploy_safe dry-run in the backend. App: iPhone 17 simulator build and scripts/test_body_capture.swift with Shared/BodyCapture.swift. DEBUG --body-preview supplies only synthetic data and blocks personal capture. Physical AppIntent, widget installation, phone microphone and field judgement still need device validation.

Backend starts from frozen A42 77ea082; iOS starts from shipped build17 source3aeaa1c. Production's separate local d5560c4 is untouched. Do not deploy/reset production from this document. Exact code/review/evidence and any later release belong in the shared A2-043 task record. No push, merge, restart or TestFlight upload has occurred for this candidate.
