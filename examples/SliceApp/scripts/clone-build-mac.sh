#!/bin/sh
# Independent clean clone build for SliceApp (macOS). RightKit requires a branch-attached PRIMARY checkout; a linked
# worktree does not qualify (release-invocation.mjs assertPrimaryReleaseCheckout). So the build runs in a fresh
# `git clone` of origin at an exact commit, in a scratch location outside the primary checkout.
#
# usage: clone-build-mac.sh --commit <sha> [--origin <url>] [--scratch <dir>] [--rightkit <dir>]
#                           [--stage doctor|build] [--dry-run]
#   --commit    required; 7-40 hex chars, resolved to the full SHA after fetch
#   --origin    default: git@github.com:bogusyogi/swiftright.git
#   --scratch   default: $HOME/.swiftright-clean/<sha12>  (refused if inside the primary checkout)
#   --rightkit  default: /Volumes/D/claude/rightkit  (local @rightkit/release package; read-only use)
#   --stage     doctor = right-release doctor only; build (default) = right-release release --tier patch --no-upload (build, sign, notarize, staple, seal; NO upload)
#   --dry-run   parse and validate arguments, print the plan, touch nothing
# Never runs upload/publish-update. The commit must already be pushed to origin.
#
# package.json pins @rightkit/release as link:../../../rightkit/packages/release (relative to examples/SliceApp).
# The clone therefore sits at <scratch>/swiftright and <scratch>/rightkit is a symlink to --rightkit, so the link
# resolves without editing any tracked file (the tree stays clean, as the source gate requires).
set -eu

ORIGIN="git@github.com:bogusyogi/swiftright.git"
COMMIT=""
SCRATCH=""
RIGHTKIT="/Volumes/D/claude/rightkit"
STAGE="build"
DRY=0
die() { echo "clone-build-mac: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --commit) [ $# -ge 2 ] || die "--commit needs a value"; COMMIT="$2"; shift 2 ;;
    --origin) [ $# -ge 2 ] || die "--origin needs a value"; ORIGIN="$2"; shift 2 ;;
    --scratch) [ $# -ge 2 ] || die "--scratch needs a value"; SCRATCH="$2"; shift 2 ;;
    --rightkit) [ $# -ge 2 ] || die "--rightkit needs a value"; RIGHTKIT="$2"; shift 2 ;;
    --stage) [ $# -ge 2 ] || die "--stage needs a value"; STAGE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$COMMIT" ] || die "--commit is required"
printf '%s' "$COMMIT" | grep -Eq '^[0-9a-fA-F]{7,40}$' || die "--commit must be 7-40 hex characters"
case "$STAGE" in doctor|build) ;; *) die "--stage must be doctor or build" ;; esac
SHORT=$(printf '%s' "$COMMIT" | cut -c1-12)
[ -n "$SCRATCH" ] || SCRATCH="$HOME/.swiftright-clean/$SHORT"

HERE=$(cd "$(dirname "$0")" && pwd)
PRIMARY=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || true)
case "$SCRATCH/" in
  "$PRIMARY"/*) [ -z "$PRIMARY" ] || die "--scratch must be outside the primary checkout ($PRIMARY)" ;;
esac
BRANCH="sr0-clean-$SHORT"
CLONE="$SCRATCH/swiftright"

echo "plan: clone $ORIGIN at $COMMIT -> $CLONE (branch $BRANCH)"
echo "plan: $SCRATCH/rightkit -> $RIGHTKIT"
echo "plan: examples/SliceApp: pnpm install --frozen-lockfile; pnpm exec right-release $STAGE --platform mac --config right-release.config.mjs"
if [ "$DRY" = 1 ]; then echo "dry-run: nothing executed"; exit 0; fi

[ -d "$RIGHTKIT/packages/release" ] || die "RightKit release package not found: $RIGHTKIT/packages/release"
[ ! -e "$CLONE" ] || die "$CLONE already exists; pick a new --scratch or remove it yourself"
mkdir -p "$SCRATCH/tools"
ln -s "$RIGHTKIT" "$SCRATCH/rightkit"

git clone --no-checkout "$ORIGIN" "$CLONE"
cd "$CLONE"
git fetch origin "$COMMIT" 2>/dev/null || true
FULL=$(git rev-parse --verify "$COMMIT^{commit}") || die "commit $COMMIT is not available from $ORIGIN (push it first)"
git checkout -q -B "$BRANCH" "$FULL"
[ "$(git rev-parse HEAD)" = "$FULL" ] || die "HEAD is not $FULL after checkout"
[ -z "$(git status --porcelain)" ] || die "fresh clone is not clean"
echo "clone at $FULL on branch $BRANCH"

cd examples/SliceApp
pnpm install --frozen-lockfile
[ -z "$(git status --porcelain)" ] || die "pnpm install dirtied the tree (lockfile out of date?); source gate would refuse"
if [ "$STAGE" = doctor ]; then
  pnpm exec right-release doctor --platform mac --config right-release.config.mjs
else
  pnpm exec right-release release --tier patch --platform mac --no-upload --config right-release.config.mjs
fi
echo "done: $STAGE at $FULL (clone: $CLONE). Artifacts under $CLONE/examples/SliceApp/dist and the RightKit state root."
