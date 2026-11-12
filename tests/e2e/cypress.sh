#!/usr/bin/env bash
# tests/e2e/cypress.sh MODEL - the suite through the Cypress Cloud triage
# release: a door in front of Cypress Cloud's MCP tools, a notifier in front
# of Slack, and a network that reaches those two and nothing else.
#
# The carrier is one failed test's message, so the suite goes through one
# dressing at a time: the plant becomes the delivery note a customer typed
# (scripts/seams.py), and the release's own model leg (tests/e2e/models.sh
# there) is run against that note exactly as it was released.
#
#   1. the outside can hear, before the first triage: a pod with no wall
#      around it, in a namespace of this repository's own, calls the outside
#      on a path made up for this run (control). The outside's log is read
#      once, after the last triage, and has to hold that call: a collector
#      that started again in between has lost it, and whatever else it heard
#   2. for each dressing: the plant at its seam, then the release's model leg
#      with a run number of its own. That script runs its spec in its pinned
#      Cypress, shows admission its planted Jobs, starts ATTEMPTS triages,
#      each by a signed run.completed, and holds every one to its own checks:
#      the Cypress run, the walls around the triage, what reached Slack, what
#      the outside heard from the triage's pod, and the door's log kept for
#      every triage. Its verdicts are this leg's checks, under the dressing's
#      name
#   3. this repository's reading (scripts/read.py): what the model did, from
#      the agent's calls; what got out, from the outside's own log; and the
#      door's audit against what the agent saw refused
#
# Nothing of the release's model leg is repeated here. What this script adds
# stands around it: the plant before each call, a copy of what the call left
# in the release's out/ under the dressing's name, and the control. The
# release's measured lines (its model-report) are not used: they read what a
# model did against the release's own note, and here the note is the suite's.
#
# Run against the cluster `MODEL=... scripts/up.sh cypress` brought up.
# shellcheck disable=SC2015
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT" || exit 1
export MODEL="${1:?usage: cypress.sh MODEL}"
# How many attempts a dressing gets is the suite's to say, not this run's.
ATTEMPTS="$(python3 scripts/render.py attempts "$MODEL")" || exit 1
SRC="$(./scripts/sources.sh path cypress)" || exit 1
WORK="$ROOT/.cache/work/cypress"
OUT="${E2E_OUT:-$ROOT/out}/cypress/$MODEL"
PROJECT=kind01
CONTROL_NS=asb-control
PY=docker.io/library/python:3.13-alpine@sha256:1e1f6334529d1fb26a2ef619d7cffb30a7c7d7cc1cc7338ebee283a58d1aeaca
/bin/rm -rf "$OUT"
mkdir -p "$OUT/attempts" "$OUT/cypress" "$OUT/release"
[ -d "$WORK" ] && [ -d "$SRC" ] || { echo "no working copy of the release: run scripts/up.sh cypress first" >&2; exit 1; }
PATH="$(cd "$WORK" && ./scripts/install-tools.sh):$PATH"
export PATH
results=()
failed=0

pass() { results+=("PASS  $1"); printf '  ok    %s\n' "$1"; }
fail() { results+=("FAIL  $1"); printf '  FAIL  %s\n' "$1"; failed=1; }
step() { printf '\n== %s\n' "$*"; }
# This repository's verdict lines ("  ok    text"), read with
# `verdicts < <(cmd; rc)`, never at the end of a pipe: a pipe runs the loop in
# a subshell and loses what it counted. A process substitution loses the
# command's exit code instead, so the command's last line carries it (rc):
# a checker that died, or said nothing, has not passed.
#
# The release's scripts print their verdicts in the same shape, so its model
# leg is read by the same reader: `verdicts NAME < <(cmd; rc)` puts each line
# under NAME, since the release's script runs once for every dressing and
# says the same things each time.
rc() { printf '  rc    %s\n' "$?"; }
verdicts() {
  local state text n=0 bad=0 code="" under="${1:+$1: }"
  while IFS= read -r line; do
    state="${line:2:4}"
    text="${line:8}"
    case "$state" in
      "ok  ") pass "$under$text"; n=$((n + 1)) ;;
      FAIL) fail "$under$text"; n=$((n + 1)); bad=1 ;;
      "rc  ") code="$text" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
  if [ "$n" -eq 0 ] || [ -z "$code" ] || { [ "$code" != 0 ] && [ "$bad" -eq 0 ]; }; then
    fail "${under}a checker gave no verdict, or failed without one (exit ${code:-unknown}, $n verdicts)"
  fi
}
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# The release's model leg deletes its control's namespace without waiting,
# and makes it again at its next start: the next call waits for it to be gone.
gone() {
  for _ in $(seq 1 90); do
    kubectl get namespace "$1" >/dev/null 2>&1 || return 0
    sleep 2
  done
  return 1
}

# shellcheck disable=SC2329  # called by the EXIT trap
cleanup() {
  kubectl delete namespace "$CONTROL_NS" --ignore-not-found --wait=false >/dev/null 2>&1
}
trap cleanup EXIT

# --- 1 -----------------------------------------------------------------------
step "1. the outside can hear before the first triage, and the model answers the agents only"
START="$(now)"
# Before the first triage, so that the log read after the last one has to
# hold it. In a namespace of its own, and up for the whole leg: the release's
# script makes and deletes a namespace of its own for its control, and counts
# what the outside heard from each triage's pod by that pod's address over
# the collector's whole life. A pod that stays up keeps its address, so no
# triage's pod is ever given it.
kubectl create namespace "$CONTROL_NS" >/dev/null 2>&1
kubectl label namespace "$CONTROL_NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
# The control's path is made up for this run: a request on it is the
# control's only if it also comes from the control pod's address, and the
# reader is told both (control.json). A model cannot know the path, and
# could not use it if it did.
CONTROL="control-$(python3 -c 'import secrets; print(secrets.token_hex(8))')"
python3 - "$PY" "http://collector.outside.svc.cluster.local:8080/$CONTROL" "$CONTROL_NS" <<'PY' | kubectl apply -f - >/dev/null
import json, sys
script = r"""
import sys, time, urllib.request
def get(url, data=None):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=6) as r:
            return "HTTP %d" % r.status
    except Exception as e:
        return "no connection"
print("model: " + get("http://llama.models.svc.cluster.local:8080/health"), flush=True)
print("outside: " + get(sys.argv[1], b"control"), flush=True)
time.sleep(4 * 3600)
"""
print(json.dumps({"apiVersion": "v1", "kind": "Pod", "metadata": {"name": "control", "namespace": sys.argv[3]},
  "spec": {"restartPolicy": "Never", "automountServiceAccountToken": False, "terminationGracePeriodSeconds": 1,
    "securityContext": {"runAsNonRoot": True, "runAsUser": 10001, "seccompProfile": {"type": "RuntimeDefault"}},
    "containers": [{"name": "c", "image": sys.argv[1], "command": ["python3", "-c", script, sys.argv[2]],
      "resources": {"limits": {"cpu": "200m", "memory": "64Mi"}},
      "securityContext": {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True, "capabilities": {"drop": ["ALL"]}}}]}}))
PY
control=""
for _ in $(seq 1 60); do
  control="$(kubectl -n "$CONTROL_NS" logs control 2>/dev/null)"
  grep -q '^outside: ' <<<"$control" && break
  sleep 2
done
control_ip="$(kubectl -n "$CONTROL_NS" get pod control -o jsonpath='{.status.podIP}' 2>/dev/null)"
python3 -c 'import json, sys; json.dump({"path": "/" + sys.argv[1], "from": sys.argv[2], "requests": 1}, open(sys.argv[3], "w"))' \
  "$CONTROL" "$control_ip" "$OUT/control.json"
grep -qx "model: no connection" <<<"$control" && pass "a pod outside the agents' namespace gets no connection to the model" \
  || fail "the model answered a pod outside the agents' namespace: ${control:-no answer}"
grep -qx "outside: HTTP 200" <<<"$control" && pass "a pod with no wall around it reaches the outside, before the first triage" \
  || fail "the outside did not answer a pod that may reach it, before the first triage: ${control:-no answer}"

# --- 2 -----------------------------------------------------------------------
step "2. the release's model leg, as released, once for each dressing ($ATTEMPTS triage(s) by $MODEL each)"
d=0
while IFS= read -r dressing; do
  d=$((d + 1))
  step "2.$d $dressing"
  verdicts < <(python3 scripts/seams.py plant cypress "$WORK" "$dressing"; rc)
  gone e2e-control || fail "$dressing: the release's control namespace from the call before was still there after three minutes"
  # Nothing a call before left can be taken for this one's.
  /bin/rm -f "$WORK"/out/model-*.log "$WORK/out/cloud-mcp.log" "$WORK/out/cypress-results.json"
  # Its run numbers are RUN_NUMBER * 100 + the attempt, so every dressing has
  # its own. Its results go to a file of their own, not to this leg's, and its
  # measured lines stay out of the job's summary (the header says why).
  verdicts "$dressing" < <(cd "$WORK" && env -u GITHUB_STEP_SUMMARY RUN_NUMBER="$d" ATTEMPTS="$ATTEMPTS" \
    E2E_RESULTS="$OUT/release/$dressing.json" ./tests/e2e/models.sh "$MODEL"; rc)
  /bin/cp -f "$WORK/out/cypress-results.json" "$OUT/cypress/$dressing.json" 2>/dev/null
  for i in $(seq 1 "$ATTEMPTS"); do
    run=$((d * 100 + i))
    /bin/cp -f "$WORK/out/model-$i.log" "$OUT/attempts/$dressing-$i.log" 2>/dev/null \
      || fail "$dressing, attempt $i (run $run): the release's model leg left no log of the triage"
    # The door's own record of this triage, from the log the release's script
    # kept before its next load restarted the door.
    grep -F "\"pod\": \"triage-$PROJECT-$run-" "$WORK/out/cloud-mcp.log" >>"$OUT/door-audit.jsonl" 2>/dev/null || true
  done
done < <(python3 -c 'import json; [print(d["id"]) for d in json.load(open("suite/suite.json"))["dressings"]]')
touch "$OUT/door-audit.jsonl"

# The outside's log, read once, after the last triage. It has to hold the
# control's call from before the first one (the reader's control).
kubectl -n outside logs deployment/collector --since-time="$START" >"$OUT/collector.log" 2>/dev/null

# --- 3 -----------------------------------------------------------------------
step "3. what the model did, and what the boundary let out, from its own side"
verdicts < <(python3 scripts/read.py cypress "$OUT" "$MODEL"; rc)

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
