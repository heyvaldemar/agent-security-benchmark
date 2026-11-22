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
#
# A leg that makes a namespace for its control is held to one more thing
# (control_namespace): a namespace of that name still terminating is waited
# for and never made over, one that never goes fails the leg, and so does one
# that cannot be made. `kubectl` and `sleep` are stand-ins here; what the
# stand-in was asked is kept in a file, because the leg asks from a subshell.
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

  made="$(grep -c '^control_namespace() {' "$script")"
  if [ "$made" = 0 ]; then
    grep -q 'kubectl create namespace' "$script" && { echo "$script makes a namespace without control_namespace"; bad=1; }
    continue
  fi
  calls="$(grep -c '^control_namespace ' "$script")"
  bare="$(awk '/^control_namespace\(\) \{/,/^\}/ {next} /kubectl create namespace/' "$script" | grep -c .)"
  if [ "$calls" != 1 ] || [ "$bare" != 0 ]; then
    echo "$script: the control's namespace is made $calls time(s) through control_namespace and $bare time(s) without it"
    bad=1
  fi
  eval "$(awk '/^control_namespace\(\) \{/,/^\}/' "$script")"
  asked="$(mktemp)"
  sleep() { :; }
  # A namespace in state $state: terminating (for two looks, then gone),
  # stuck (terminating for ever), refused (cannot be made), or fresh.
  kubectl() {
    case "$1 $2" in
      "get namespace")
        echo look >>"$asked"
        if grep -q '^made$' "$asked"; then printf Active; return 0; fi
        case "$state" in
          terminating) [ "$(grep -c '^look$' "$asked")" -le 2 ] && { printf Terminating; return 0; }; return 1 ;;
          stuck) printf Terminating; return 0 ;;
          *) return 1 ;;
        esac ;;
      "create namespace")
        [ "$state" = refused ] && return 1
        echo "made after $(grep -c '^look$' "$asked") looks" >>"$asked"
        echo made >>"$asked"
        return 0 ;;
      *) return 0 ;;
    esac
  }
  try() {  # try STATE WANT_FAILED WANT_LINE WHAT
    state="$1"
    : >"$asked"
    results=()
    failed=0
    control_namespace e2e-control >/dev/null
    if [ "$failed" != "$2" ] || { [ -n "$3" ] && ! grep -qx "$3" "$asked"; } || { [ -z "$3" ] && grep -q '^made$' "$asked"; }; then
      echo "$script: $4 leaves failed=$failed and $(tr '\n' ';' <"$asked")"
      bad=1
    fi
  }
  try terminating 0 "made after 3 looks" "a namespace still terminating is not waited for before it is made"
  try stuck 1 "" "a namespace that never finishes terminating"
  try refused 1 "" "a namespace that cannot be made"
  try fresh 0 "made after 1 looks" "a cluster with no such namespace"
  /bin/rm -f "$asked"
  unset -f control_namespace kubectl sleep try
done
[ "$bad" = 0 ] && echo "every leg's verdict reader fails a checker that dies, says nothing, or exits non-zero, and a control's namespace is made only once the one before it is gone"
exit "$bad"
