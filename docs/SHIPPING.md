# Shipping and Testing — Alicia iOS + Backend

Companion to `AGENTS.md`. That file governs *how we work on the code*; this one
governs *how code reaches Hector's hands*, on either endpoint, without anyone
racing anyone else.

Read it before shipping a build, running a branch backend, or merging to `main`.

---

## 0. The principle

**`main` is the stable, deployed thing. Testing does not require `main`.**

Hector wants to try Alicia on iOS and Telegram continuously — several times a
day, from branches, while other work is in flight. Nothing about that requires
touching `main`, and using `main` as the route to his phone is what turns it
into a racing surface.

`main` moves when something has been reviewed and chosen. Not to test it.

## 1. Status — what is actually available today

The principle above is settled. Most of the mechanism is **not built yet**.
This section is the honest inventory; treat anything marked BLOCKED as
something to sequence around, not to attempt.

| Capability | Status |
|---|---|
| Ship `main` to TestFlight from the canonical checkout | **Works** (`ship.sh`, used for 1.0 build 1) |
| Cable install to Pandaiux from any checkout | **Works**, given a provisioned worktree (§2.1) |
| Ship a **branch** to TestFlight | **BLOCKED** — needs §2.1, §2.2, §2.3 |
| Two agents shipping concurrently | **BLOCKED** — needs §2.3; until then, sequence and say so in chat |
| Point the **phone** at a branch backend | **BLOCKED** — no in-app switcher; `opus/backend-switcher` |
| Run a **branch backend** at all | **BLOCKED** — the port is hardcoded (§4) |

**Until the BLOCKED rows clear, branch testing means the cable path**, one
agent at a time, and `main` still does not move to test anything.

## 2. What has to be built before branch shipping is safe

Three gaps, each of which currently fails *silently* — which is why none of
them is "just be careful".

### 2.1 Worktree configuration provisioning

`Alicia/Secrets.plist` carries the backend URL and token and is **gitignored**,
so a fresh worktree does not have it. `AliciaConfig` then falls back to
`MockAliciaService`, the archive succeeds, the upload succeeds, and Hector
installs a build showing **sample data** that looks alive and ignores the
backend entirely. Nothing in the pipeline complains.

Required:

- A provisioning step that links the canonical secret into a new worktree —
  the path `Alicia/Secrets.plist` is already gitignored, so a symlink there
  cannot be committed:

  ```bash
  ln -s /Users/alicia/AliciaApp/Alicia/Secrets.plist \
        /Users/alicia/AliciaApp-worktrees/<name>/Alicia/Secrets.plist
  ```

- **`ship.sh` must refuse to upload** a build whose `.app` lacks
  `Secrets.plist`, exactly as it already refuses one that isn't
  distribution-signed. A silent mock build reaching Hector's phone is worse
  than a failed ship.
- Never copy the token into a file the repo can see, and never echo it.

### 2.2 Builds must say what they are

TestFlight shows `1.0 (7)` and nothing else. Two agents shipping two branches
produce builds Hector cannot tell apart — and he is the one choosing between
them, often hours later, from a phone.

`AppVersion.tag` (`Alicia/DesignSystem/ContourWaves.swift`) is shown on the
Alicia tab and must carry the branch on any non-`main` build:

```
v36 · opus/presence
```

Derive it at build time from the current branch rather than hand-editing, so
it cannot be forgotten or left stale. A `main` build carries the bare tag.

### 2.3 A serialized build-number allocator

`CURRENT_PROJECT_VERSION` is unique **per app**, not per branch. Two agents
incrementing independently collide, and App Store Connect rejects the loser
minutes later, server-side, long after the shipper has moved on.

A clock-derived number is *not* sufficient: two ships in the same minute still
collide, and it silently depends on clocks agreeing.

Required: **a serialized allocator** — one caller at a time, authoritative
answer, no negotiation between agents.

- State lives outside both repos (e.g. under `~/.appstoreconnect/`), shared by
  every worktree, mutated under a lock so concurrent shippers cannot receive
  the same number.
- Reconcile against App Store Connect's highest existing build at allocation
  time, so losing local state self-heals rather than colliding.
- **Inject at build time** — `xcodebuild … CURRENT_PROJECT_VERSION=<n>` —
  rather than writing it into `project.pbxproj`.

### 2.4 Generated version values are never committed

Because §2.2 and §2.3 are computed at build time, **no generated version
change is committed at all.** There is no bump to stage, nothing to push, and
no reason for a ship to touch git.

This also resolves the `/ship-ios` tension: an unattended ship from Dispatch
neither commits nor pushes, and `main` is untouched by construction.

## 3. Rules

### R1 — Never push to `main` to test something

If the reason for the push is "so I can try it", the answer is a branch build
or the cable. `main` is for promotion only (§5).

### R2 — Never run a branch in a canonical checkout

Do not `git checkout` a branch in `/Users/alicia/alicia` or
`/Users/alicia/AliciaApp`. The first is the live Alicia Hector talks to; the
second is what he opens in Xcode.

### R3 — `ship.sh` never pushes

Shipping and publishing are separate acts. The script uploads to Apple and
stops.

### R4 — One shipper at a time, announced

Until §2.3 lands this is a correctness requirement, not etiquette. After it
lands it remains courtesy: two TestFlight uploads in flight give Hector two
notifications and no way to tell them apart until each finishes processing.
Say in chat that you are shipping, and from what branch.

### R5 — State what you verified, and on what

Simulator compilation is not visual QA — the iOS 26 simulator substitutes
custom fonts. Device results come from Pandaiux. Say which you did.

## 4. Backend branches — future infrastructure

**This does not exist yet.** `skills/ios_api.py` hardcodes `start_ios_api(port=8766)`,
called once from `alicia.py`. There is no port override and no second-instance
runner. `alicia_labs.py` / `com.alicia.labs.plist` is an *evaluation bot* with
its own token — a useful precedent for a second process, not a branch-backend
mechanism.

Running a branch backend therefore requires, as its own piece of work:

- A port override on `start_ios_api` (env var or argument), so a sidecar does
  not fight production for `:8766`.
- A second bot token, and a clear label so Hector always knows which Alicia
  answered.
- Its own launchd plist, running from a **worktree**, never the production
  checkout (R2), using the production venv — the ignored `venv/` exists only
  there: `/Users/alicia/alicia/venv/bin/python3.11`.

Build this when a branch actually changes backend behavior. Until then, iOS
branches test against production Alicia, which is read-mostly for them.

## 5. Pointing the phone at another backend

`AliciaConfig` resolves `UserDefaults("alicia.baseURL"/"alicia.token")` →
`Secrets.plist` → mock.

**On a physical device there is currently no way to change this without a
rebuild.** `defaults write` on the Mac edits the Mac's own preferences and
never reaches the phone; it works only for the **Simulator**, and even then via
the simulator's own domain:

```bash
# Simulator only — NOT the device
xcrun simctl spawn booted defaults write com.myalicia.app \
  alicia.baseURL 'http://100.81.90.92:8767'
```

For the device, the options today are a debugger-set `UserDefaults` value with
the phone attached, or a rebuild with a different `Secrets.plist`. Closing this
is what `opus/backend-switcher` is for.

**Trap, whichever route:** a `UserDefaults` override beats `Secrets.plist`
*forever*, including a stale token that 401s long after the plist is right, and
nothing in the UI shows it. Any switcher must make the active override visible
and clearable.

## 6. Promotion — when `main` finally moves

`main` moves when Hector chooses the thing. The gate:

1. PR open, reviewed by the *other* agent from the committed branch (never a
   dirty worktree), handed off via `docs/AI_HANDOFF_TEMPLATE.md`.
2. Simulator build green (`AGENTS.md` §6).
3. Backend `python3 tests/smoke_test.py` green if `~/alicia` is touched, with
   the exit code captured directly — never through a pipe.
4. Device-verified on Pandaiux for anything visual.
5. `AppVersion.tag` resolves to the shipping version with no branch suffix.
6. One integrator merges. Agents do not race merges.
7. Canonical checkout updated fast-forward only:
   `git pull --ff-only origin main`.

A backend change an iOS change depends on gets its own PR, linked, with the
merge and deploy order stated.

## 7. Where this leaves the `/ship-ios` skill

`~/.claude/skills/ship-ios/SKILL.md` predates `AGENTS.md` and tells Opus to
commit and push the build bump to `main`. Under R1/R3 and §2.4 it must not:
nothing is generated into the repo, so there is nothing to commit.

Hector calls it from Dispatch while away from the Mac, so it must still run
unattended end to end — the fix is that it stops touching git, never that it
starts asking.

---

## Amendment proposed for `AGENTS.md` §5

`AGENTS.md` is Codex-owned; this pointer is proposed rather than applied:

> - Shipping, branch builds, and backend sidecars follow `docs/SHIPPING.md`.
>   `main` moves on promotion only; testing never requires it. Branch
>   TestFlight shipping is unavailable until that document's §2 lands.
