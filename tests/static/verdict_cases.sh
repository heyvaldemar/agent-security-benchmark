#!/usr/bin/env bash
# tests/static/verdict_cases.sh - the legs' verdict readers, shown checkers
# that must not pass.
#
# Each leg reads its checkers' lines through `verdicts < <(cmd; rc)`. A
# process substitution drops the command's exit code, so a checker that dies
# before it prints, or prints nothing, would leave no verdict and a green
# leg. The reader is held here to five shapes of checker, in every leg's
# script: one that dies, one that passes, one that passes and then exits
# non-zero, one that fails, and one whose exit code never arrives.
# pass and fail are called by the readers this file evals out of each leg.
# shellcheck disable=SC2015,SC2329
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
bad=0
for script in tests/e2e/sandbox.sh tests/e2e/flagship.sh tests/e2e/cypress.sh; do
  results=()
  failed=0
  pass() { results+=("PASS  $1"); }
  fail() { results+=("FAIL  $1"); failed=1; }
  eval "$(awk '/^rc\(\) \{/,/^\}/' "$script")"
  eval "$(awk '/^verdicts\(\) \{/,/^\}/' "$script")"
  declare -F verdicts >/dev/null && declare -F rc >/dev/null || { echo "$script has no verdict reader"; bad=1; continue; }
  expect() {  # expect WANT_FAILED WHAT
    [ "$failed" = "$1" ] || { echo "$script: $2 leaves failed=$failed"; bad=1; }
    results=()
    failed=0
  }
  verdicts < <(python3 -c "import sys; sys.exit(3)"; rc)
  expect 1 "a checker that dies before it prints"
  verdicts < <(printf '  ok    fine\n'; rc)
  expect 0 "a checker that passes"
  verdicts < <(printf '  ok    fine\n'; false; rc)
  expect 1 "a checker that passes and then exits non-zero"
  verdicts < <(printf '  FAIL  bad\n'; false; rc)
  expect 1 "a checker that fails"
  verdicts < <(printf '  ok    fine\n')
  expect 1 "a checker whose exit code never arrives"
  unset -f verdicts rc
done
[ "$bad" = 0 ] && echo "every leg's verdict reader fails a checker that dies, says nothing, or exits non-zero"
exit "$bad"
