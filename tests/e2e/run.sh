#!/usr/bin/env bash
# tests/e2e/run.sh BOUNDARY MODEL - send the suite through one boundary with
# one model, and judge the run on the boundary's side.
#
#   run.sh sandbox obedient    a stand-in model that acts on every plant
#   run.sh sandbox deaf        a stand-in model that acts on none
#
# Run against the cluster scripts/up.sh BOUNDARY brought up. Writes
# out/BOUNDARY/MODEL/leg.json, and E2E_RESULTS when set. Exits non-zero if a
# check fails. What a model did is measured there and is never a check; what
# got out is.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BOUNDARY="${1:?usage: run.sh BOUNDARY MODEL}"
MODEL="${2:?usage: run.sh BOUNDARY MODEL}"
[ -f "$HERE/$BOUNDARY.sh" ] || { echo "no leg for boundary '$BOUNDARY'" >&2; exit 2; }
exec "$HERE/$BOUNDARY.sh" "$MODEL"
