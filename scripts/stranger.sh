#!/usr/bin/env bash
# stranger.sh <dir> - what anyone can check about the records in <dir> with
# nothing but the files and cosign. <dir> is runs/ in a copy of the branch
# `status`, or docs/runs here.
#
#   - cosign holds every signed record to the bundle beside it, as signed by
#     this repository's e2e workflow on main and nobody else's;
#   - cosign refuses a copy of each with one byte appended: a verifier that
#     accepts anything would pass the line above;
#   - a bundle has its record beside it, and no record made after the first
#     signed one is without a bundle (run ids only grow);
#   - at least one signed record was there: a check that looked at nothing
#     has shown nothing.
#
# The Status workflow runs it on a clone of the branch it has just written,
# in a job with no token and no permission (.github/workflows/status.yml).
# tests/static/stranger_cases.py shows it the directories it must refuse.
set -uo pipefail
dir="${1:?usage: stranger.sh <directory of records>}"
SIGNED_BY="https://github.com/heyvaldemar/agent-security-benchmark/.github/workflows/e2e.yml@refs/heads/main"
ISSUER="https://token.actions.githubusercontent.com"

if ! command -v cosign >/dev/null; then
  echo "cosign is not on PATH (scripts/install-tools.sh puts it there)"
  exit 1
fi
if [ ! -d "$dir" ]; then
  echo "$dir is not a directory"
  exit 1
fi

ask() {
  cosign verify-blob "$1" --bundle "$2" --certificate-identity "$SIGNED_BY" \
    --certificate-oidc-issuer "$ISSUER" >/dev/null 2>&1
}

work="$(mktemp -d)"
trap '/bin/rm -rf "$work"' EXIT
signed=0
unsigned=0
bad=0
first=""
for bundle in "$dir"/*.json.sigstore.json; do
  [ -e "$bundle" ] || continue
  rec="${bundle%.sigstore.json}"
  name="$(basename "$rec")"
  if [ ! -f "$rec" ]; then
    echo "$name: a signature with no record beside it"
    bad=1
    continue
  fi
  signed=$((signed + 1))
  id="${name%.json}"
  case "$id" in
    '' | *[!0-9]*) ;;
    *) if [ -z "$first" ] || [ "$id" -lt "$first" ]; then first="$id"; fi ;;
  esac
  if ! ask "$rec" "$bundle"; then
    echo "$name: cosign does not verify it, with the bundle beside it, as signed by this repository's e2e workflow on main"
    bad=1
    continue
  fi
  /bin/cp -f "$rec" "$work/changed.json"
  printf ' ' >>"$work/changed.json"
  if ask "$work/changed.json" "$bundle"; then
    echo "$name: cosign accepts a copy with one byte appended"
    bad=1
  fi
done

# Records made before the repository was public carry no signature. One made
# after the first signed record has lost its bundle somewhere.
for rec in "$dir"/*.json; do
  [ -e "$rec" ] || continue
  case "$rec" in *.sigstore.json) continue ;; esac
  [ -f "$rec.sigstore.json" ] && continue
  name="$(basename "$rec")"
  id="${name%.json}"
  case "$id" in '' | *[!0-9]*) continue ;; esac
  if [ -n "$first" ] && [ "$id" -gt "$first" ]; then
    echo "$name: a record with no signature, made after the first signed one ($first.json)"
    bad=1
  else
    unsigned=$((unsigned + 1))
  fi
done

if [ "$signed" -eq 0 ]; then
  echo "no signed record in $dir: nothing was checked"
  exit 1
fi
[ "$bad" -eq 0 ] || exit 1
echo "$signed signed records in $dir: cosign verifies each and refuses a copy of each with one byte appended; $unsigned older records carry no signature"
