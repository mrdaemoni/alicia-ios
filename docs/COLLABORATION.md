# Shared focus — A2-010

The collaboration sheet is shared by the five-tab app. Us and
Alicia show up to three active goals and the current connection or agreement even when no
morning episode has played. Dialogue and Context enrichment open the same work.
The source baseline is 55798db; release evidence belongs to the shared A2-010
RELEASE.md. A compiled candidate is not a shipped TestFlight build.

Goals are Hector's explicit words, with a desired outcome, reason, state and
Less / Normal / More attention. Alicia proposes connections with captured source
passages and a reason for returning now. Use keeps the connection in view;
Clarify requests a grounded question. Neither commits Hector to an action.

A2-011 makes concurrent goals visible. The summary shows the active count, up to
three independently tappable goals ordered by attention, and Add goal at the top.
Open together retains all goals, including paused/completed ones, with Add goal
above their details. The three-row summary is a display choice, not a storage cap.
Adding creates a separate identity; editing targets only the selected goal.
The direct Add goal route uses the existing retained draft and immutable save.
Historical notification routes decode without the optional new-goal flag.
Backend A2-011 also reserves three goal records in Qwen's compact context;
full-context conversation and the background worker retain every active goal.
Release evidence is in the shared A2-011 task, not inferred from compilation.

Consider a commitment opens an editable action, owner and review condition.
Commit explicitly submits that agreement. Alicia's prepared result is labelled
as a draft or finding. Hector can record an observation without completing the
agreement, complete it with an outcome, pause it or change course while keeping
its history. Goal edits remain separate from completed actions or kept learnings.
Alicia can also prepare internal research directly toward a saved active goal.
Those results appear under that goal with their evidence; they do not require or
create an agreement. An optional result goal_id keeps older result payloads readable.

Evidence opens captured passages, source identity and line references, with a
separate current-file read. Voice references open the existing original-recording
review, not a generated recreation. Time, entry point and acoustic/context
observations do not establish Hector's feelings; he can add explicit current
context. Natural read-aloud uses the shared immersive reader and may prepare a new
cloud audio file. Existing Dialogue provider comparisons and training consent
remain unchanged.

## State and recovery

Core/Collaboration.swift defines the wire types and CollaborationStore. One
monotonic shared snapshot drives all views. Older reads cannot replace newer
revisions. A single durable outbox preserves the exact UUID and submitted fields
through uncertain replies and app relaunch. Incomplete success remains pending;
a definite rejection unlocks the retained draft. Entity editors preserve their
original revision with draft words so a stale edit requires deliberate reload.
Opening or syncing shared focus retries pending receipts before fetching fresh state.
The collaboration endpoint's valid HTTP 400 rejection unlocks the draft; auth,
server and malformed responses remain unconfirmed. Reload current version fetches
fresh state before replacing draft words and revision, retaining both if it fails.
Context input is locked while its exact submitted receipt awaits confirmation.
Acknowledgments clear only the draft bound to that exact receipt, including when
its editor is closed. An on-screen editor closes after a later retry confirms it.

GET /api/collaboration reads the shared state. POST /api/collaboration accepts
explicit goal, connection, commit, agreement, outcome, signal, settings, refresh
and seen mutations. GET /api/collaboration/source resolves an evidence ID against
its captured connection or prepared result. Networking uses AliciaService and
LiveAliciaService; views use AppStore's CollaborationStore. Backend deploys first.

## Purposeful returns

CollaborationNotifier replaces legacy ThoughtReturn scheduling when the shared
payload is available. It schedules the backend's actual candidate, preserving
its exact goal/connection/agreement identity. It does not allocate daily slots.
Local quiet hours are 9am–7pm. New shared revisions invalidate an older local
schedule; an ordinary chat does not cancel an agreement. Stop cancels on this
phone immediately, persists locally, and queues the server setting. It does not
cancel goals. Telegram returns have their own explicit setting.
An existing local Stop from the earlier ThoughtReturn feature migrates once,
including when background sync runs first. A deliberate new Allow clears it.
Older scheduler snapshots are ignored. Once the collaboration payload has been
seen, an unavailable endpoint cannot revive legacy background broadcasts.

A notification opens the exact connection or agreement and records viewing only
when that target exists. The queued navigation identity survives a cold launch.
Scheduling is not delivery, engagement, agreement or completion. There is no
APNs integration: another device's changes are learned at the next sync, and iOS
permission/Focus/background scheduling can delay or suppress a return.

## Verification

--collaboration-preview forces the mock provider, isolated collaboration defaults
and generated voice fixture. --collaboration-target-preview also opens an exact
fixture connection, without scheduling a real notification. New Swift lifecycle
checks exercise actual models, outbox and notifier methods with suspended fake
IO. Temporary XCUITest targets exercise real controls without changing the app
project. Evidence is under Documents/Alicia-development/tasks/A2-010/evidence/ios.
Together with --collaboration-preview, --collaboration-reduce-motion-preview
selects the existing deterministic presence still state. It does not change the
simulator's accessibility settings; system Reduce Motion still takes precedence.
Physical microphone/headset, VoiceOver and notification delivery remain device
checks. Simulator images do not prove model quality or an outcome for Hector.
