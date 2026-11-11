#!/usr/bin/env bash
# tests/e2e/flagship.sh MODEL - the suite through the flagship's release.
#
#   1. the working copy is the release with the plants at its seams and
#      nothing else (scripts/seams.py check)
#   2. the release's own checks, on this runner: its tests/e2e/run.sh
#   3. the attempts: the release's own agent (evals/harness.py) through the
#      suite's six tasks and two of the release's ordinary ones, three
#      attempts each, judged by the release's own checker (scripts/evals.sh),
#      whose gates are kept as the boundary's own verdict
#   4. this repository's reading of the same logs, on two levels
#      (scripts/read.py): what the model did, from the agent's calls; what
#      left, from the records service's log of its outbox
#
# Run against the cluster `MODEL=... scripts/up.sh flagship` brought up.
# shellcheck disable=SC2015
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT" || exit 1
export MODEL="${1:?usage: flagship.sh MODEL}"
SRC="$(./scripts/sources.sh path flagship)" || exit 1
WORK="$ROOT/.cache/work/flagship"
OUT="${E2E_OUT:-$ROOT/out}/flagship/$MODEL"
/bin/rm -rf "$OUT"
mkdir -p "$OUT/state"
[ -d "$WORK" ] && [ -d "$SRC" ] || { echo "no working copy of the flagship: run scripts/up.sh flagship first" >&2; exit 1; }
PATH="$(cd "$WORK" && ./scripts/install-tools.sh):$PATH"
export PATH OFFER_PATTERNS=off TASK_FLOOR=off
results=()
failed=0

pass() { results+=("PASS  $1"); printf '  ok    %s\n' "$1"; }
fail() { results+=("FAIL  $1"); printf '  FAIL  %s\n' "$1"; failed=1; }
step() { printf '\n== %s\n' "$*"; }
verdicts() {
  local state text
  while IFS= read -r line; do
    state="${line:2:4}"
    text="${line:8}"
    case "$state" in
      "ok  ") pass "$text" ;;
      FAIL) fail "$text" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}
counts() { python3 -c '
import json, sys
try:
    c = json.load(open(sys.argv[1])).get("checks", [])
except (OSError, ValueError):
    c = []
print("%d of %d" % (sum(1 for x in c if x.get("passed")), len(c)))' "$1"; }

# --- 1 -----------------------------------------------------------------------
step "1. the working copy is the release, with the plants at its seams"
verdicts < <(python3 scripts/seams.py check flagship "$WORK")

# --- 2 -----------------------------------------------------------------------
step "2. the release's own checks, on this runner"
(cd "$WORK" && E2E_RESULTS="$OUT/own-e2e.json" ./tests/e2e/run.sh) >"$OUT/own-e2e.log" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "the flagship's own e2e passes on this runner: $(counts "$OUT/own-e2e.json") checks" \
  || { fail "the flagship's own e2e failed here (rc=$rc): $(counts "$OUT/own-e2e.json") checks"; grep -E '^\s+FAIL' "$OUT/own-e2e.log" | head -20; }

# --- 3 -----------------------------------------------------------------------
step "3. three attempts by $MODEL for each of the suite's dressings, by the release's own agent"
(cd "$WORK" && EVALS_OUT="$OUT/state" EVALS_RESULTS="$OUT/own-evals.json" ./scripts/evals.sh) >"$OUT/own-evals.log" 2>&1
rc=$?
grep -E '^\s+(PASS|FAIL|\.\.)' "$OUT/own-evals.log" | sed 's/^/  the release says:/'
[ $rc -eq 0 ] && pass "the flagship's own gates held: $(counts "$OUT/own-evals.json")" \
  || fail "the flagship's own gates did not hold (rc=$rc): $(counts "$OUT/own-evals.json")"

# --- 4 -----------------------------------------------------------------------
step "4. what the model did, and what the boundary let out, from its own side"
verdicts < <(python3 scripts/read.py flagship "$OUT" "$MODEL")

printf '\n'
printf '%s\n' "${results[@]}"
if [ -n "${E2E_RESULTS:-}" ] && [ -s "$OUT/leg.json" ]; then
  mkdir -p "$(dirname "$E2E_RESULTS")"
  printf '%s\n' "${results[@]}" | python3 -c '
import json, sys
checks = [{"name": l[6:].rstrip("\n"), "passed": l.startswith("PASS")} for l in sys.stdin if l.strip()]
leg = json.load(open(sys.argv[2]))
json.dump({"boundary": leg["boundary"], "model": leg["model"], "checks": checks, "measured": leg["measured"]},
          open(sys.argv[1], "w"), indent=1)' "$E2E_RESULTS" "$OUT/leg.json"
fi
exit $failed
