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

## 1. Why this works — the facts it rests on

Verified 2026-08-16; if you think one of these has changed, check before
relying on it.

- **`ship.sh` does not touch git.** It archives the *working tree*, re-signs
  for distribution, and uploads to Apple. No commit, no push, no branch
  requirement. Any worktree can ship to TestFlight.
- **The cable path is likewise local** (`xcodebuild` → `devicectl install`).
- **The backend is a launchd process reading a checkout**
  (`com.alicia.agent` ← `/Users/alicia/alicia`). A branch can run as a *second*
  process with its own bot token and port — the pattern already in use for
  `com.alicia.labs` / `alicia_labs.py`. Production Alicia keeps answering.
- **The app chooses its backend at runtime**: `AliciaConfig` resolves
  `UserDefaults("alicia.baseURL"/"alicia.token")` → `Secrets.plist` → mock.

So a branch can reach Hector's phone and his Telegram without `main` moving.

## 2. Rules

### R1 — Never push to `main` to test something

If the reason for the push is "so I can try it", the answer is a branch build.
`main` is for promotion only (§4).

### R2 — Every build must say what it is

TestFlight shows `1.0 (7)` and nothing else. Two agents shipping two branches
produce builds Hector cannot tell apart — and he is the one deciding between
them, often hours later, from a phone.

`AppVersion.tag` (`Alicia/DesignSystem/ContourWaves.swift`) is shown on the
Alicia tab and **must carry the branch** when the build is not from `main`:

```
v36 · opus/presence
```

A build from `main` carries the bare tag. If Hector cannot name the branch he
is holding, the build should not have been shipped.

### R3 — Build numbers are global; derive them, don't coordinate them

`CURRENT_PROJECT_VERSION` is unique **per app**, not per branch. Two agents
incrementing independently collide, and App Store Connect rejects the second
one minutes later, server-side.

Do not solve this with a talking protocol. **Derive the build number from the
clock**, which is monotonic and needs no coordination:

```
CURRENT_PROJECT_VERSION = YYMMDD.HHMM      # e.g. 260816.0912
```

Unique across agents and branches by construction, and it tells you when the
build was made. `ship.sh` owns this; agents do not hand-edit it.

### R4 — Never run a branch in the production checkout

Do not `git checkout` a branch in `/Users/alicia/alicia` or
`/Users/alicia/AliciaApp`. The first is the live agent Hector talks to; the
second is what he opens in Xcode. A branch backend runs from its own worktree
as a second launchd process (§3.2).

### R5 — `ship.sh` never pushes

Shipping and publishing are separate acts. The script uploads to Apple and
stops. Commit the build-number change to the branch you are on; `main` is
untouched.

### R6 — One shipper at a time per endpoint

Two TestFlight uploads in flight at once is legal but confusing — Hector gets
two notifications and no way to tell which is which until each finishes
processing. Say in chat that you are shipping, and what branch.

## 3. Recipes

### 3.1 Ship a branch to Hector's phone

```bash
cd /Users/alicia/AliciaApp-worktrees/<your-worktree>
./ship.sh                      # archive → distribution-sign → upload
```

TestFlight installs it over the air. `main` is not involved. Confirm the tag
carries your branch (R2) before you ship, not after.

### 3.2 Run a branch backend Hector can talk to

Production Alicia must keep running. Start the branch as a sidecar:

1. Work in a backend worktree, never the production checkout (R4).
2. Give it its own Telegram bot token and its own port (`ALICIA_IOS_PORT`),
   following `ALICIA_LABS.md` and `com.alicia.labs.plist`.
3. Run it from the production venv — the ignored `venv/` exists only there:
   `/Users/alicia/alicia/venv/bin/python3.11`.
4. Tell Hector which bot is the branch. Two Alicias answering with no label is
   worse than one.

### 3.3 Point the phone at a branch backend

Today this needs a debugger or a rebuild — there is no settings UI, which is
why `opus/backend-switcher` exists. Until it lands:

```bash
# on the Mac, against a Debug build
defaults write com.myalicia.app alicia.baseURL 'http://100.81.90.92:8767'
```

**Trap:** a `UserDefaults` override beats `Secrets.plist` *forever*, including
a stale token that 401s long after the plist is right, and nothing in the UI
shows it. Clear it when you are done:

```bash
defaults delete com.myalicia.app alicia.baseURL alicia.token
```

## 4. Promotion — when `main` finally moves

`main` moves when Hector chooses the thing. The gate:

1. PR open, reviewed by the *other* agent from the committed branch (never a
   dirty worktree), handed off via `docs/AI_HANDOFF_TEMPLATE.md`.
2. Simulator build green (`AGENTS.md` §6).
3. Backend `python3 tests/smoke_test.py` green if `~/alicia` is touched, with
   the exit code captured directly — never through a pipe.
4. Device-verified on Pandaiux for anything visual. The simulator substitutes
   custom fonts; it is not final visual QA.
5. `AppVersion.tag` set to the shipping version, branch suffix **removed**.
6. One integrator merges. Agents do not race merges.
7. Canonical checkout updated fast-forward only:
   `git pull --ff-only origin main`.

A backend change that an iOS change depends on gets its own PR, linked, with
the merge and deploy order stated.

## 5. Where this leaves the `/ship-ios` skill

`~/.claude/skills/ship-ios/SKILL.md` predates `AGENTS.md` and told Opus to
commit and push the build bump to `main`. Under R1/R5 it must not. It ships
the branch it is standing in, commits the bump there, and stops.

Hector calls it from Dispatch while away from the Mac, so it must still run
unattended end to end — the fix is *where it commits*, never a prompt.

---

## Amendment proposed for `AGENTS.md` §5

`AGENTS.md` is Codex-owned; this pointer is proposed rather than applied:

> - Shipping, branch builds, and backend sidecars follow `docs/SHIPPING.md`.
>   `main` moves on promotion only; testing never requires it.
