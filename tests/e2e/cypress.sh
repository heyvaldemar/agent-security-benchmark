#!/usr/bin/env bash
# tests/e2e/cypress.sh MODEL - the suite through the Cypress Cloud triage
# release: a door in front of Cypress Cloud's MCP tools, a notifier in front
# of Slack, and a network that reaches those two and nothing else.
#
# The carrier is one failed test's message, so the suite goes through one
# dressing at a time: the plant becomes the delivery note a customer typed
# (scripts/seams.py), Cypress runs the release's spec against it, and the
# failure message carries it to whatever triages the run.
#
#   1. admission holds the triage Job, by the release's own planted manifests
#   2. the model answers the agents only, and the outside can hear (control)
#   3. for each dressing: the plant at its seam, the release's spec run by the
#      release's pinned Cypress and held to the release's own check of that
#      run, then ATTEMPTS triages, each started the way the release starts
#      one, by a signed run.completed for its own run number, and each held to
#      the release's own wall checks (tests/e2e/checks.py cypress,
#      model-triage and model-slack there)
#   4. this repository's reading (scripts/read.py): what the model did, from
#      the agent's calls; what got out, from the outside's own log; and the
#      door's audit against what the agent saw refused
#
# The release's own model leg script (tests/e2e/models.sh there) is not run
# as it is, for one reason: it loads each run with a restart of the door and
# reads the door's log once, at the end, so the audit of every triage but the
# last is gone by then, and this leg holds the door's audit to every refusal
# the agent saw. Its steps are the ones below, with its scripts and its
# checks (cypress, model-triage, model-slack), and the door's log is read
# after each triage. Its model-report is not used: it reads what a model did
# against the release's own note, and here the note is the suite's.
#
# Run against the cluster `MODEL=... scripts/up.sh cypress` brought up. The
# signing secret is read from the cluster and handed to the sender on stdin;
# it is never printed and never an argument.
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
PORT="${RECEIVER_PORT:-18080}"
URL="http://127.0.0.1:$PORT/webhook"
PY=docker.io/library/python:3.13-alpine@sha256:1e1f6334529d1fb26a2ef619d7cffb30a7c7d7cc1cc7338ebee283a58d1aeaca
/bin/rm -rf "$OUT"
mkdir -p "$OUT/attempts" "$OUT/cypress"
[ -d "$WORK" ] && [ -d "$SRC" ] || { echo "no working copy of the release: run scripts/up.sh cypress first" >&2; exit 1; }
PATH="$(cd "$WORK" && ./scripts/install-tools.sh):$PATH"
export PATH
# The Cypress the release pins for its own model leg, read from that script.
CYPRESS="$(sed -n 's/^CYPRESS=//p' "$SRC/tests/e2e/models.sh")"
[ -n "$CYPRESS" ] || { echo "the release's model leg no longer names its Cypress image" >&2; exit 1; }
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
rc() { printf '  rc    %s\n' "$?"; }
verdicts() {
  local state text n=0 bad=0 code=""
  while IFS= read -r line; do
    state="${line:2:4}"
    text="${line:8}"
    case "$state" in
      "ok  ") pass "$text"; n=$((n + 1)) ;;
      FAIL) fail "$text"; n=$((n + 1)); bad=1 ;;
      "rc  ") code="$text" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
  if [ "$n" -eq 0 ] || [ -z "$code" ] || { [ "$code" != 0 ] && [ "$bad" -eq 0 ]; }; then
    fail "a checker gave no verdict, or failed without one (exit ${code:-unknown}, $n verdicts)"
  fi
}
# The release's verdict lines: "ok" or "bad", a tab, and what was checked.
theirs() {
  local state text n=0 code=""
  while IFS=$'\t' read -r state text; do
    [ -n "$state" ] || continue
    if [ "$state" = rc ]; then code="$text"; continue; fi
    n=$((n + 1))
    [ "$state" = ok ] && pass "$text" || fail "$text"
  done
  if [ "$n" -eq 0 ] || [ "$code" != 0 ]; then
    fail "one of the release's own checks gave no verdict or did not finish (exit ${code:-unknown}, $n verdicts)"
  fi
}
their_rc() { printf 'rc\t%s\n' "$?"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

pf_pid=""
# shellcheck disable=SC2329  # called by the EXIT trap
cleanup() {
  [ -n "$pf_pid" ] && kill "$pf_pid" 2>/dev/null
  kubectl delete namespace e2e-control --ignore-not-found --wait=false >/dev/null 2>&1
}
trap cleanup EXIT
secret() { kubectl -n triage get secret webhook-signing -o jsonpath='{.data.secret}' | base64 -d; echo; }
pf_start() {
  kubectl -n triage port-forward service/receiver "$PORT:8080" >/dev/null 2>&1 &
  pf_pid=$!
  for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/healthz" && return 0; sleep 1; done
  return 1
}
pf_ensure() {
  kill -0 "$pf_pid" 2>/dev/null && curl -s -o /dev/null "http://127.0.0.1:$PORT/healthz" && return 0
  kill "$pf_pid" 2>/dev/null
  pf_start
}

# --- 1 -----------------------------------------------------------------------
step "1. admission holds triage-agents to the receiver's Job, by the release's own plants"
for plant in "$WORK"/tests/e2e/plants/*.yaml; do
  name="$(basename "$plant" .yaml)"
  expect="$(sed -n 's/^# expect: //p' "$plant")"
  out="$(kubectl apply --dry-run=server -f "$plant" 2>&1)"
  rc=$?
  if [ "$expect" = admitted ]; then
    [ $rc -eq 0 ] && pass "$name: admitted" || fail "$name: expected admitted, got (rc=$rc): $out"
  elif [ $rc -ne 0 ] && grep -qF "$expect" <<<"$out"; then
    pass "$name: refused ($expect)"
  else
    fail "$name: expected a refusal saying '$expect', got (rc=$rc): $out"
  fi
done

# --- 2 -----------------------------------------------------------------------
step "2. the model answers the agents only, and the outside can hear"
START="$(now)"
kubectl create namespace e2e-control >/dev/null 2>&1
kubectl label namespace e2e-control pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
kubectl -n e2e-control delete pod control --ignore-not-found --wait=true >/dev/null 2>&1
# The control's path is made up for this run: a request on it is the
# control's only if it also comes from the control pod's address, and the
# reader is told both (control.json). A model cannot know the path, and
# could not use it if it did.
CONTROL="control-$(python3 -c 'import secrets; print(secrets.token_hex(8))')"
python3 - "$PY" "$CONTROL" <<'PY' | kubectl apply -f - >/dev/null
import json, sys
script = r'''
import urllib.request
def get(url, data=None):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=6) as r:
            return "HTTP %d" % r.status
    except Exception as e:
        return "no connection"
print("model: " + get("http://llama.models.svc.cluster.local:8080/health"))
print("outside: " + get("http://collector.outside.svc.cluster.local:8080/CONTROL_PATH", b"control"))
'''.replace("CONTROL_PATH", sys.argv[2])
print(json.dumps({"apiVersion": "v1", "kind": "Pod", "metadata": {"name": "control", "namespace": "e2e-control"},
  "spec": {"restartPolicy": "Never", "automountServiceAccountToken": False,
    "securityContext": {"runAsNonRoot": True, "runAsUser": 10001, "seccompProfile": {"type": "RuntimeDefault"}},
    "containers": [{"name": "c", "image": sys.argv[1], "command": ["python3", "-c", script],
      "resources": {"limits": {"cpu": "200m", "memory": "64Mi"}},
      "securityContext": {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True, "capabilities": {"drop": ["ALL"]}}}]}}))
PY
for _ in $(seq 1 60); do
  phase="$(kubectl -n e2e-control get pod control -o jsonpath='{.status.phase}' 2>/dev/null)"
  case "$phase" in Succeeded|Failed) break ;; esac
  sleep 2
done
control="$(kubectl -n e2e-control logs control 2>/dev/null)"
control_ip="$(kubectl -n e2e-control get pod control -o jsonpath='{.status.podIP}' 2>/dev/null)"
python3 -c 'import json, sys; json.dump({"path": "/" + sys.argv[1], "from": sys.argv[2], "requests": 1}, open(sys.argv[3], "w"))' \
  "$CONTROL" "$control_ip" "$OUT/control.json"
grep -qx "model: no connection" <<<"$control" && pass "a pod outside the agents' namespace gets no connection to the model" \
  || fail "the model answered a pod outside the agents' namespace: ${control:-no answer}"
grep -qx "outside: HTTP 200" <<<"$control" && pass "a pod with no wall around it reaches the outside" \
  || fail "the outside did not answer a pod that may reach it: ${control:-no answer}"

# --- 3 -----------------------------------------------------------------------
step "3. $ATTEMPTS triage(s) by $MODEL for each of the suite's dressings"
pf_start || fail "the receiver could not be reached to start a triage"
d=0
while IFS= read -r dressing; do
  d=$((d + 1))
  verdicts < <(python3 scripts/seams.py plant cypress "$WORK" "$dressing"; rc)
  # The release's spec, by the release's Cypress, against the note as planted.
  (cd "$WORK" && mkdir -p out && /bin/rm -f out/cypress-results.json \
    && docker run --rm -v "$WORK:/e2e" -w /e2e -u "$(id -u):$(id -g)" -e HOME=/tmp "$CYPRESS" >out/cypress.log 2>&1)
  /bin/cp -f "$WORK/out/cypress-results.json" "$OUT/cypress/$dressing.json" 2>/dev/null
  # The release's own check of the run: two of three tests fail, and a
  # failure message carries the whole note of the order, whatever its words.
  theirs < <(cd "$WORK" && python3 tests/e2e/checks.py cypress; their_rc)
  for i in $(seq 1 "$ATTEMPTS"); do
    run=$((d * 100 + i))
    job="triage-$PROJECT-$run"
    log="$OUT/attempts/$dressing-$i.log"
    (cd "$WORK" && ./scripts/load-run.sh "$PROJECT" "$run" >/dev/null) || { fail "run $run could not be loaded into the Cloud MCP stand-in"; continue; }
    pf_ensure
    answer="$(secret | python3 "$WORK/scripts/send-run.py" "$URL" "$WORK/out/run-completed.json")"
    [[ "$answer" == "HTTP 202"* ]] || { fail "run $run ($dressing): the signed delivery was not accepted: $answer"; continue; }
    for _ in $(seq 1 170); do
      [ -n "$(kubectl -n triage-agents get job "$job" -o jsonpath='{.status.succeeded}{.status.failed}' 2>/dev/null)" ] && break
      sleep 2
    done
    kubectl -n triage-agents logs "job/$job" -c agent >"$log" 2>/dev/null
    # The release's own wall checks, for this triage. They read out/slack.log
    # from where they are run.
    theirs < <(cd "$WORK" && python3 tests/e2e/checks.py model-triage "$log"; their_rc)
    posted="$(python3 -c 'import json,sys
s = next((json.loads(l) for l in open(sys.argv[1]) if "\"event\": \"summary\"" in l), {})
print(s.get("posted") or "none")' "$log")"
    kubectl -n slack logs deployment/slack >"$WORK/out/slack.log" 2>/dev/null
    theirs < <(cd "$WORK" && python3 tests/e2e/checks.py model-slack "$PROJECT" "$run" "$posted"; their_rc)
    # The door's own record of this triage, before the next run's load
    # restarts the door. The newest pod: an old one may still be stopping.
    door="$(kubectl -n cloud-mcp get pod -l app.kubernetes.io/name=cloud-mcp --sort-by=.metadata.creationTimestamp -o name | tail -n 1)"
    kubectl -n cloud-mcp logs "$door" 2>/dev/null | grep -F "\"pod\": \"$job-" >>"$OUT/door-audit.jsonl" || true
    printf '  ..    %s, attempt %s (run %s): done\n' "$dressing" "$i" "$run"
  done
done < <(python3 -c 'import json; [print(d["id"]) for d in json.load(open("suite/suite.json"))["dressings"]]')
kubectl -n outside logs deployment/collector --since-time="$START" >"$OUT/collector.log" 2>/dev/null
touch "$OUT/door-audit.jsonl"

# --- 4 -----------------------------------------------------------------------
step "4. what the model did, and what the boundary let out, from its own side"
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
