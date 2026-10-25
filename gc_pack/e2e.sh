#!/usr/bin/env bash
# End-to-end harness for the Gas City pack in gc_pack/decisions, run against a
# real gc. A maintainer tool: it lives outside the pack root, so gc never sees
# it as part of the pack.
#
# Each scenario pins one claim gc_pack/decisions/README.md makes about gc
# behaviour, in its own throwaway city, and prints one PASS or FAIL line naming
# that claim. The script exits 1 if any scenario fails.
#
# Usage: gc_pack/e2e.sh
#   E2E_ONLY="s2_rig_level s9_cache_wipe"  run only these scenarios
#   E2E_VERBOSE=1                           print every scenario's log
#   E2E_KEEP=1                              keep the sandbox for inspection
#   E2E_TMPDIR=<dir>                        where the sandbox goes (default
#                                           RUNNER_TEMP, then TMPDIR, then /tmp)
#
# Binaries are read from the environment, falling back to PATH:
#   GC_BIN         gc (CI pins 1.5.1)
#   BD_BIN         bd, at least 1.3.0 (gc init refuses older)
#   DOLT_BIN       dolt
#   DECISIONS_BIN  decisions; unset, it is compiled from this checkout with
#                  `dart compile exe`, so the stubs and the binary agree
#
# The pack under test is the one committed at HEAD, imported through the same
# git + subpath + sha: resolver adopters use. Uncommitted pack edits are not
# seen; commit them first.
#
# Isolation: HOME, GC_HOME, the XDG directories and TMUX_TMPDIR all live under
# one temp root, inherited GC_*, BEADS_* and TMUX variables are dropped, and
# GC_HOME is deliberately not $HOME/.gc (gc treats that path as the real,
# machine-wide home). Every city is created with --no-start and nothing here
# runs `gc start`, so no supervisor, controller or agent session is launched.
# On exit the dolt and bd processes the cities started are killed and the
# temp root is removed.

# Setup aborts on any error; the scenarios below turn -e off and report their
# own failures.
set -euo pipefail

die() {
  printf 'e2e: %s\n' "$*" >&2
  exit 2
}

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
PACK=$REPO/gc_pack/decisions

resolve_bin() { # resolve_bin <name> <env var> <its value>
  local bin=${3:-$(command -v "$1" || true)}
  [ -n "$bin" ] || die "$1 not found: set $2 or put it on PATH"
  [ -x "$bin" ] || die "$1 at $bin is not executable"
  case $bin in /*) ;; *) bin=$PWD/$bin ;; esac
  printf '%s\n' "$bin"
}

# Read the binaries before the GC_* sweep below drops GC_BIN.
GC_REAL=$(resolve_bin gc GC_BIN "${GC_BIN:-}") || exit 2
BD_REAL=$(resolve_bin bd BD_BIN "${BD_BIN:-}") || exit 2
DOLT_REAL=$(resolve_bin dolt DOLT_BIN "${DOLT_BIN:-}") || exit 2
DECISIONS_REAL=
if [ -n "${DECISIONS_BIN:-}" ]; then
  DECISIONS_REAL=$(resolve_bin decisions DECISIONS_BIN "$DECISIONS_BIN") || exit 2
fi

SHA=$(git -C "$REPO" rev-parse HEAD) || die "cannot read HEAD of $REPO"
SRC="file://$REPO//gc_pack/decisions"
if [ -n "$(git -C "$REPO" status --porcelain -- gc_pack/decisions)" ]; then
  printf 'e2e: note: gc_pack/decisions has uncommitted changes; testing HEAD %s\n' "$SHA" >&2
fi

# ---- sandbox ---------------------------------------------------------------

base=${E2E_TMPDIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}
ROOT=$(mktemp -d "${base%/}/gc-e2e.XXXXXX") || die "cannot create a temp root under $base"
# gc and dolt record physical paths; matching survivors below needs the same.
ROOT=$(cd "$ROOT" && pwd -P)

cleanup() {
  local pids pid i
  set +e
  # Everything a city starts (bd's dolt sql-server and db-proxy-child) carries
  # a path under ROOT in its command line; nothing else on the machine does.
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pids=$(pgrep -f -- "$ROOT" || true)
    [ -n "$pids" ] || break
    if [ "$i" -eq 1 ]; then
      printf 'e2e: stopping %s sandbox process(es)\n' "$(printf '%s\n' "$pids" | wc -l | tr -d ' ')" >&2
    fi
    for pid in $pids; do
      [ "$pid" = "$$" ] && continue
      if [ "$i" -lt 6 ]; then kill "$pid" 2>/dev/null; else kill -9 "$pid" 2>/dev/null; fi
    done
    sleep 0.5
  done
  if pids=$(pgrep -f -- "$ROOT"); then
    printf 'e2e: processes still running under %s: %s\n' "$ROOT" "$pids" >&2
  fi
  if [ -n "${E2E_KEEP:-}" ]; then
    printf 'e2e: kept %s\n' "$ROOT" >&2
  else
    rm -rf "$ROOT"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

while IFS= read -r var; do
  unset "$var"
done < <(compgen -e | grep -E '^(GC_|BEADS_)')
unset TMUX TMUX_PANE

export HOME=$ROOT/home
export GC_HOME=$ROOT/gc-home
export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share
export XDG_STATE_HOME=$HOME/.local/state
export XDG_RUNTIME_DIR=$ROOT/run
export TMUX_TMPDIR=$ROOT/run
export GC_DISABLE_USAGE_METRICS=1
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$GC_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" \
  "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$ROOT/bin" "$ROOT/bin-nodec" "$ROOT/bin-fake64"
chmod 700 "$XDG_RUNTIME_DIR"

# An isolated GC_HOME seeds its own supervisor.toml; write one anyway so that
# even an accidental supervisor could only bind loopback on a private port.
cat >"$GC_HOME/supervisor.toml" <<EOF
[supervisor]
bind = "127.0.0.1"
port = $((20000 + RANDOM % 20000))
EOF

cat >"$HOME/.gitconfig" <<'EOF'
[user]
	name = gc-e2e
	email = gc-e2e@example.invalid
[init]
	defaultBranch = main
[advice]
	detachedHead = false
EOF

if [ -z "$DECISIONS_REAL" ]; then
  command -v dart >/dev/null || die "set DECISIONS_BIN, or install dart so it can be compiled"
  (cd "$REPO/cli/dart/decisions" && dart pub get >/dev/null &&
    dart compile exe bin/decisions.dart -o "$ROOT/decisions-exe" >/dev/null) ||
    die "dart compile exe of cli/dart/decisions failed"
  DECISIONS_REAL=$ROOT/decisions-exe
fi
[ -x "$DECISIONS_REAL" ] || die "decisions at $DECISIONS_REAL is not executable"

for dir in bin bin-nodec bin-fake64; do
  ln -s "$GC_REAL" "$ROOT/$dir/gc"
  ln -s "$BD_REAL" "$ROOT/$dir/bd"
  ln -s "$DOLT_REAL" "$ROOT/$dir/dolt"
done
ln -s "$DECISIONS_REAL" "$ROOT/bin/decisions"
printf '#!/bin/sh\nexit 64\n' >"$ROOT/bin-fake64/decisions"
chmod +x "$ROOT/bin-fake64/decisions"

export PATH="$ROOT/bin:$PATH"
# For "decisions is not on PATH": the sandbox tools plus the system dirs only.
NODEC_PATH="$ROOT/bin-nodec:/usr/bin:/bin:/usr/sbin:/sbin"
if PATH=$NODEC_PATH command -v decisions >/dev/null; then
  die "a decisions binary sits in a system dir ($(PATH=$NODEC_PATH command -v decisions)); cannot test its absence"
fi
FAKE64_PATH="$ROOT/bin-fake64:$PATH"

dolt config --global --add user.name gc-e2e >/dev/null
dolt config --global --add user.email gc-e2e@example.invalid >/dev/null

# A second pack source with two commits, A and B, differing only in the
# description: the fixture for the upgrade and one-pin scenarios.
UP_REPO=$ROOT/upgrade-src
mkdir -p "$UP_REPO/gc_pack"
git -C "$REPO" archive HEAD gc_pack/decisions | tar -x -C "$UP_REPO"
git -C "$UP_REPO" init -q
git -C "$UP_REPO" add -A
git -C "$UP_REPO" commit -qm A
UP_A=$(git -C "$UP_REPO" rev-parse HEAD)
sed 's/^description = ".*"$/description = "upgrade fixture, commit B"/' \
  "$UP_REPO/gc_pack/decisions/pack.toml" >"$UP_REPO/pack.toml.new"
mv -f "$UP_REPO/pack.toml.new" "$UP_REPO/gc_pack/decisions/pack.toml"
git -C "$UP_REPO" commit -qam B
UP_B=$(git -C "$UP_REPO" rev-parse HEAD)
UP_SRC="file://$UP_REPO//gc_pack/decisions"

export REPO PACK SHA SRC ROOT NODEC_PATH FAKE64_PATH UP_SRC UP_A UP_B
set +e

printf 'e2e: gc %s; %s; %s\n' "$(gc version 2>/dev/null | head -n1)" \
  "$(bd version 2>/dev/null | head -n1)" "$(dolt version 2>/dev/null | head -n1)"
printf 'e2e: sandbox %s\n' "$ROOT"
printf 'e2e: pack %s at %s\n' "$SRC" "$SHA"

# ---- helpers (each scenario runs in a subshell; fail exits it) --------------

OUT=
fail() {
  printf 'FAILED: %s\n' "$*"
  exit 1
}

# run <cmd...>: run, echo the command and its output to the log, keep the
# output in $OUT and the status in $RC. Never fails by itself.
run() {
  printf '+ %s\n' "$*"
  OUT=$("$@" 2>&1) && RC=0 || RC=$?
  [ -z "$OUT" ] || printf '%s\n' "$OUT" | sed 's/^/  | /'
  printf '  (exit %s)\n' "$RC"
}

ok() { # ok <cmd...>: must exit 0
  run "$@"
  [ "$RC" -eq 0 ] || fail "expected success: $*"
}

fails_with() { # fails_with <text> <cmd...>: must exit non-zero, mentioning text
  local want=$1
  shift
  run "$@"
  [ "$RC" -ne 0 ] || fail "expected failure ($want), got success: $*"
  case $OUT in
    *"$want"*) ;;
    *) fail "expected the failure to mention '$want': $*" ;;
  esac
}

has() { # has <text>...: $OUT mentions every text
  local want
  for want in "$@"; do
    case $OUT in *"$want"*) ;; *) fail "expected output to mention '$want'" ;; esac
  done
}

lacks() { # lacks <text>...: $OUT mentions none of them
  local want
  for want in "$@"; do
    case $OUT in *"$want"*) fail "expected output not to mention '$want'" ;; esac
  done
}

new_city() { # new_city <dir>: a minimal city, never started
  ok gc init --template minimal --default-provider claude --providers claude \
    --skip-provider-readiness --no-start --name "$(basename "$1")" "$1"
}

new_rig() { # new_rig <dir>: a one-commit git repo
  mkdir -p "$1"
  git -C "$1" init -q
  printf '# %s\n' "$(basename "$1")" >"$1/README.md"
  git -C "$1" add README.md
  git -C "$1" commit -qm init
}

doctor_status() { # doctor_status: the decisions:binary status in $OUT's JSON
  printf '%s\n' "$OUT" | jq -r '[.. | objects | select(.name? == "decisions:binary") | .status] | first // empty' 2>/dev/null
}

lists_skills() { # lists_skills <agent>
  ok gc skill list --agent "$1"
  has decisions.decide decisions.ratify
}

lists_no_skills() { # lists_no_skills <agent>
  ok gc skill list --agent "$1"
  lacks decisions.decide decisions.ratify
}

# ---- scenarios -------------------------------------------------------------

s1_lint() {
  ok gc lint "$PACK"
}

s2_rig_level() {
  local dir=$ROOT/s2 status
  new_city "$dir/city"
  new_rig "$dir/app"
  cd "$dir/city" || fail "cd"
  ok gc rig add "$dir/app" --name app
  ok gc --rig app import add "$SRC" --name decisions --version "sha:$SHA"
  ok gc import check
  lists_skills app/claude
  lists_no_skills mayor

  ok gc doctor --check decisions:binary --json
  status=$(doctor_status)
  [ "$status" = ok ] || fail "decisions:binary status '$status', want ok"

  run env PATH="$NODEC_PATH" gc doctor --check decisions:binary --json
  status=$(doctor_status)
  [ "$status" = error ] || fail "without decisions on PATH: status '$status', want error"
  [ "$RC" -ne 0 ] || fail "without decisions on PATH: gc doctor exited 0"
  has 'decisions not found on PATH'

  run env PATH="$FAKE64_PATH" gc doctor --check decisions:binary --json
  status=$(doctor_status)
  [ "$status" = error ] || fail "with a decisions that exits 64: status '$status', want error"
  has 'cannot run doctor'
}

s3_materialized() {
  local dir=$ROOT/s3 stub
  new_city "$dir/city"
  new_rig "$dir/app"
  cd "$dir/city" || fail "cd"
  ok gc rig add "$dir/app" --name app
  ok gc --rig app import add "$SRC" --name decisions --version "sha:$SHA"
  run gc internal materialize-skills --agent app/claude --workdir "$dir/wd"
  case $OUT in
    *'unknown command'*)
      printf 'SKIP: this gc has no internal materialize-skills\n'
      return 0
      ;;
  esac
  [ "$RC" -eq 0 ] || fail "gc internal materialize-skills failed"
  for stub in decide ratify; do
    git -C "$REPO" show "HEAD:gc_pack/decisions/skills/$stub/SKILL.md" >"$dir/$stub.want"
    cmp "$dir/$stub.want" "$dir/wd/.claude/skills/decisions.$stub/SKILL.md" ||
      fail "materialized decisions.$stub/SKILL.md differs from the committed stub"
  done
}

s4_city_level() {
  local dir=$ROOT/s4
  new_city "$dir/city"
  new_rig "$dir/app"
  cd "$dir/city" || fail "cd"
  ok gc rig add "$dir/app" --name app
  ok gc import add "$SRC" --name decisions --version "sha:$SHA"
  grep -Eq '^[[:space:]]*\[imports\.decisions\]' pack.toml || fail "city import not in the root pack.toml as [imports.decisions]"
  ok gc import check
  lists_skills mayor
  lists_skills app/claude
}

s5_defaults() {
  local dir=$ROOT/s5
  new_city "$dir/city"
  new_rig "$dir/early"
  new_rig "$dir/late"
  cd "$dir/city" || fail "cd"
  ok gc rig add "$dir/early" --name early
  cat >>city.toml <<EOF

[defaults.rig.imports.decisions]
source = "$SRC"
version = "sha:$SHA"
EOF
  ok gc rig add "$dir/late" --name late
  has 'Import: decisions='
  # rig add copies the table but installs nothing: the city does not load
  # until gc import install runs.
  fails_with 'missing packs.lock entry' gc skill list --agent late/claude
  ok gc import install
  ok gc import check
  lists_skills late/claude
  lists_no_skills early/claude
}

s6_upgrade() {
  local dir=$ROOT/s6
  new_city "$dir/city"
  new_rig "$dir/app"
  cd "$dir/city" || fail "cd"
  ok gc rig add "$dir/app" --name app
  ok gc --rig app import add "$UP_SRC" --name decisions --version "sha:$UP_A"
  fails_with 'already exists' gc --rig app import add "$UP_SRC" --name decisions --version "sha:$UP_B"
  grep -q "sha:$UP_A" city.toml || fail "the rig import's version is not in city.toml"
  sed "s/sha:$UP_A/sha:$UP_B/" city.toml >city.toml.new && mv -f city.toml.new city.toml
  ok gc import install
  grep -q "$UP_B" packs.lock || fail "packs.lock does not record commit B"
  if grep -q "$UP_A" packs.lock; then fail "packs.lock still records commit A"; fi
  ok gc import check
  lists_skills app/claude
}

s7_one_pin() {
  local dir=$ROOT/s7
  new_city "$dir/city"
  new_rig "$dir/app"
  new_rig "$dir/other"
  cd "$dir/city" || fail "cd"
  ok gc rig add "$dir/app" --name app
  ok gc rig add "$dir/other" --name other
  ok gc --rig app import add "$UP_SRC" --name decisions --version "sha:$UP_A"
  fails_with 'incompatible pinned versions' \
    gc --rig other import add "$UP_SRC" --name decisions --version "sha:$UP_B"
  # The same conflict, written by hand in a defaults table, stops install.
  if grep -q "sha:$UP_B" city.toml; then fail "the refused import add left its pin in city.toml"; fi
  cat >>city.toml <<EOF

[defaults.rig.imports.decisions]
source = "$UP_SRC"
version = "sha:$UP_B"
EOF
  fails_with 'incompatible pinned versions' gc import install
}

s8_include() {
  local dir=$ROOT/s8
  new_city "$dir/city"
  new_rig "$dir/other"
  cd "$dir/city" || fail "cd"
  run gc rig add "$dir/other" --name other --include "$SRC"
  if [ "$RC" -eq 0 ]; then
    run gc import install
  fi
  if [ "$RC" -eq 0 ]; then
    fail "gc changed --include behaviour: revisit gc_pack/decisions/README.md"
  fi
  has 'no semver tags found'
}

s9_cache_wipe() {
  local dir=$ROOT/s9 cache
  new_city "$dir/city"
  new_rig "$dir/app"
  cd "$dir/city" || fail "cd"
  ok gc rig add "$dir/app" --name app
  ok gc --rig app import add "$SRC" --name decisions --version "sha:$SHA"
  lists_skills app/claude
  # gc reports where each skill lives; the import's cache dir is that path
  # less the pack's subpath.
  cache=$(printf '%s\n' "$OUT" | awk '$1 == "decisions.decide" { print $3 }')
  cache=${cache%/gc_pack/decisions/skills/decide/SKILL.md}
  case $cache in
    "$GC_HOME"/?*) ;;
    *) fail "cannot find the import cache dir (got '$cache')" ;;
  esac
  [ -f "$cache/gc_pack/decisions/pack.toml" ] || fail "no pack checkout at $cache"
  printf 'cache dir: %s\n' "$cache"
  rm -rf "$cache"
  fails_with 'locked but not cached' gc skill list --agent mayor
  fails_with 'locked but not cached' gc config show
  ok gc import install
  lists_skills app/claude
}

# ---- run -------------------------------------------------------------------

failures=0
scenario() { # scenario <fn> <README claim>
  local fn=$1 claim=$2 log=$ROOT/logs/$1.log rc
  case " ${E2E_ONLY:-$fn} " in *" $fn "*) ;; *) return 0 ;; esac
  mkdir -p "$ROOT/logs"
  (
    set -e
    "$fn"
  ) >"$log" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    if grep -q '^SKIP:' "$log"; then
      printf 'PASS %s: %s (%s)\n' "$fn" "$claim" "$(grep -m1 '^SKIP:' "$log")"
    else
      printf 'PASS %s: %s\n' "$fn" "$claim"
    fi
  else
    printf 'FAIL %s: %s\n' "$fn" "$claim"
    tail -n 60 "$log" | sed 's/^/    /'
    failures=$((failures + 1))
  fi
  [ -z "${E2E_VERBOSE:-}" ] || sed 's/^/    /' "$log"
}

scenario s1_lint "the pack passes gc lint"
scenario s2_rig_level "a rig import reaches only that rig's agents; decisions:binary reports ok, not-on-PATH and too-old"
scenario s3_materialized "gc links the committed stubs as decisions.decide and decisions.ratify"
scenario s4_city_level "a city import is [imports.decisions] in pack.toml and reaches the mayor and every rig's agents"
scenario s5_defaults "[defaults.rig.imports] reaches rigs added afterwards, not rigs that already exist"
scenario s6_upgrade "upgrade by moving the version and running gc import install; import add again fails with 'already exists'"
scenario s7_one_pin "one pin per city: a second pin of the same source fails with 'incompatible pinned versions'"
scenario s8_include "gc rig add --include of this pack fails with 'no semver tags found'"
scenario s9_cache_wipe "after a cache wipe the city fails to load with 'locked but not cached'; gc import install refills it"

if [ "$failures" -ne 0 ]; then
  printf 'e2e: %s scenario(s) failed\n' "$failures"
  exit 1
fi
printf 'e2e: all scenarios passed\n'
