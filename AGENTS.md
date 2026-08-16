# Alicia iOS — Rules of Engagement for AI Collaborators

This file applies to the entire repository. Codex, Opus, and any other agent
must read it before inspecting or changing code.

## 1. Read order and authority

Read, in order:

1. The current user request — it is authoritative for the task.
2. This `AGENTS.md` — collaboration, safety, and integration rules.
3. `SESSION_HANDOFF.md` — current product state, ship loop, and known gaps.
4. `CLAUDE.md` — stable architecture and design language.
5. The feature-specific document, especially `docs/MOTION_LAB.md` for
   visualization work.

When documents conflict, do not silently choose. Verify the current code and
tell Hector what differs. Preserve his explicit decisions exactly.

## 2. One agent, one branch, one worktree

`/Users/alicia/AliciaApp` is the canonical `main` checkout and the project
Hector opens in Xcode. Keep it clean. Agents do not develop there.

Every task gets a dedicated branch and worktree. Never let Codex and Opus edit
the same worktree or branch, even at different times without a handoff commit.

Literal examples — do not type angle-bracket placeholders into zsh:

```bash
cd /Users/alicia/AliciaApp
git fetch origin
mkdir -p /Users/alicia/AliciaApp-worktrees

# Codex implementation
git worktree add /Users/alicia/AliciaApp-worktrees/presence-implementation \
  -b codex/presence-implementation origin/main

# Opus critique or alternative exploration
git worktree add /Users/alicia/AliciaApp-worktrees/presence-review \
  -b opus/presence-review origin/main
```

Before editing, every agent reports:

- Branch and worktree
- Objective and non-goals
- Files it expects to own
- Whether another open branch touches those files

If two tasks need the same file, sequence them. Parallel work is allowed only
when file ownership is disjoint and the interface between the tasks is already
agreed.

## 3. Recommended Codex–Opus collaboration

Use strengths without turning them into rigid job titles:

- **Opus is especially useful for:** product intent, continuity with the full
  Alicia relationship, architectural critique, interaction language, naming,
  and reviewing whether a visual idea means what Hector intends.
- **Codex is especially useful for:** implementation, repository-wide wiring,
  debugging, instrumentation, simulator/device validation, performance work,
  and producing a reviewable PR.
- Either may propose or review. Only one agent writes a given implementation
  branch at a time.

The preferred sequence for a new visualization is:

1. **Brief:** Hector and Opus establish the experience, semantic mappings,
   constraints, and what should remain unresolved.
2. **Implementation:** Codex implements that accepted brief in a dedicated
   worktree and records any forced technical tradeoffs.
3. **Cross-review:** Opus reviews the committed diff, screenshots/video, and
   handoff—not uncommitted files—and returns specific findings.
4. **Revision:** Codex addresses accepted findings on the same implementation
   branch.
5. **Promotion:** Hector makes the final aesthetic/product call. Only then does
   the implementation move from the lab into a product surface.

For two competing explorations, create two branches from the same `origin/main`
commit. Keep both in the DEBUG lab, compare them with the same evaluation
criteria, and promote one. Do not merge both experiments into product code and
decide afterward.

## 4. Visualization promotion gate

New motion or generative visualization begins in the DEBUG-only Motion Lab.
Do not modify a shipped tab first.

Current seams:

- `Alicia/DesignSystem/AliciaPresence.swift` — reusable presence component
- `Alicia/Features/MotionLab/MotionLabView.swift` — DEBUG comparison surface
- `docs/MOTION_LAB.md` — lab controls and promotion workflow
- `Alicia/Features/Mind/MindView.swift` — hidden DEBUG entry point

A visualization may enter a product surface only after:

1. Hector selects it in the Motion Lab.
2. Its parameters have semantic meaning tied to archetype, attention, or state;
   no arbitrary “cool-looking” controls survive into production.
3. All six archetypes are visibly distinct where archetype is part of the
   brief; differences cannot be merely tiny parameter shifts.
4. Bounds and finite-value guards pass for every state/archetype.
5. Reduce Motion produces an intentional, legible alternative.
6. Animation pauses or reduces work when offscreen/backgrounded.
7. The simulator build passes and representative states are visually captured.
8. Final typography, rhythm, and performance are inspected on Pandaiux. The
   simulator is not sufficient for final visual approval.
9. `AppVersion.tag` and its date are bumped only for the version that ships.

Prefer one coherent mathematical body over mirrored or duplicated “jellyfish”
forms. Preserve the ink-on-bone visual language, deterministic drawing seeds,
and the hard prohibition on SF Symbols and emoji in the app UI.

## 5. Git and PR protocol

- Never push directly to `main`.
- Never share uncommitted work as a handoff. Make a scoped commit first.
- Inspect `git status --short --branch` and `git diff --stat` before staging.
- Stage explicit files. Do not use `git add -A` when unrelated work may exist.
- Commits describe behavioral outcomes, for example:
  `motion lab: distinguish archetypes through six geometric families`.
- Push the feature branch and open a PR. The PR description uses
  `docs/AI_HANDOFF_TEMPLATE.md`.
- One designated integrator—normally Hector or the agent Hector names—merges
  PRs serially. Two agents do not race merges into `main`.
- A private branch may rebase onto `origin/main` before review. Never rebase a
  branch another agent is using.
- If an iOS change also requires `~/alicia`, create a separate backend branch
  and PR. Link the two PRs and state the required merge/deploy order.
- After merge, update the canonical checkout only with fast-forward-only:

  ```bash
  cd /Users/alicia/AliciaApp
  git fetch origin
  git pull --ff-only origin main
  ```

## 6. Required verification

At minimum, every implementation PR runs:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme Alicia \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

For visual work, attach or link:

- Simulator screenshots for representative states
- A short recording or two-frame comparison when claiming motion
- Reduce Motion evidence
- Bounds/performance instrumentation when using Canvas or many points
- Device result on Pandaiux before declaring promotion complete

Do not call simulator compilation “final visual QA.” Do not call browser
animation performance “iOS performance.” State clearly what was and was not
verified.

## 7. Handoff contract

Every agent ending or transferring a task fills out
`docs/AI_HANDOFF_TEMPLATE.md` in the PR description or provides the same fields
in chat. A useful handoff names decisions, evidence, and unresolved questions;
it does not merely list changed files.

The receiving agent begins from the committed branch or PR, not from copied
snippets or another agent's dirty worktree. Review comments should cite files
and tight line ranges whenever possible.

## 8. Safety and preservation

- Never commit `Secrets.plist`, tokens, provisioning credentials, or derived
  build output.
- Do not rewrite Hector-approved prose, labels, animation meaning, or design
  choices while performing a technical refactor.
- Preserve pure SwiftUI and zero third-party dependencies unless Hector
  explicitly approves a dependency.
- Views use `AppStore` and the `AliciaService` seam; views do not make network
  calls directly.
- New Swift files under `Alicia/` are picked up by filesystem-synchronized
  groups. Do not edit `project.pbxproj` unless the build proves it is necessary.
- Existing user or agent changes are not cleanup material. If the worktree is
  dirty unexpectedly, stop and identify the owner before changing anything.
