#!/bin/bash
# Link the canonical, gitignored iOS backend configuration into this worktree.
# The credential remains in one place and is never printed or copied.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="${ALICIA_SECRETS_SOURCE:-/Users/alicia/AliciaApp/Alicia/Secrets.plist}"
DEST="$ROOT/Alicia/Secrets.plist"

die() {
  echo "!! $*" >&2
  exit 1
}

[ -r "$SOURCE" ] || die "canonical Secrets.plist is missing or unreadable"
plutil -lint "$SOURCE" >/dev/null || die "canonical Secrets.plist is invalid"

if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  [ -r "$DEST" ] || die "existing worktree Secrets.plist is unreadable"
  plutil -lint "$DEST" >/dev/null \
    || die "existing worktree Secrets.plist is invalid"
  echo "==> worktree Secrets.plist is already provisioned"
  exit 0
fi

ln -s "$SOURCE" "$DEST"
[ -r "$DEST" ] || die "failed to provision worktree Secrets.plist"
git -C "$ROOT" check-ignore -q Alicia/Secrets.plist \
  || die "Alicia/Secrets.plist is not ignored; remove the link before committing"

echo "==> worktree Secrets.plist linked securely"
