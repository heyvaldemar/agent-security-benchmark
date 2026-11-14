#!/usr/bin/env bash
# stranger.sh <dir> [<kept>] - what anyone can check about the records in
# <dir> with nothing but the files, cosign and python3. <dir> is runs/ in a
# copy of the branch `status`, or docs/runs here.
#
#   - every record's name is a run id, and the record inside is that run's:
#     a signed record under another run's name is refused;
#   - cosign holds every signed record to the bundle beside it, as signed by
#     this repository's e2e workflow on main and nobody else's;
#   - cosign refuses a copy of each with one byte appended: a verifier that
#     accepts anything would pass the line above, and so would a copy that
#     was never made, so the copy is read back before it is shown;
#   - a record with no signature is one of the eight made before the
#     repository was public, and has the sha256 this script carries for it;
#   - a bundle has its record beside it;
#   - at least one signed record was there: a check that looked at nothing
#     has shown nothing;
#   - with <kept> (docs/runs): every signed record in <kept> is in <dir>, the
#     same two files byte for byte, so a record the README cites cannot leave
#     the branch unnoticed; a name both hold is one file; and a <kept> with
#     no signed record in it fails, having held <dir> to nothing.
#
# Nothing the script holds a directory to is read from that directory. The
# Status workflow runs it on a clone of the branch it has just written, in a
# job with no token and no permission (.github/workflows/status.yml).
# tests/static/stranger_cases.py shows it the directories it must refuse.
set -uo pipefail
dir="${1:?usage: stranger.sh <directory of records> [<directory of records it must hold>]}"
kept="${2:-}"
SIGNED_BY="https://github.com/heyvaldemar/agent-security-benchmark/.github/workflows/e2e.yml@refs/heads/main"
ISSUER="https://token.actions.githubusercontent.com"
# The runs recorded before the repository went public on 2026-11-12, when a
# record was not signed: a public transparency log is no place for a private
# repository's name. A list, because a rule read from the directory under
# inspection ("older than the first signed one") moves with whoever writes
# there, and with each record's sha256, because nothing else holds a file
# that carries no signature. The hashes are of the files as the branch and
# docs/runs held them on 2026-11-14. No run after these may be unsigned.
BEFORE_PUBLIC="
43110837569 c87a1293d38aaa2a50926a30a4caa2eda62c6435d546132fa08937a0b205d518
43115393032 05f7b7ccad43c22cee87cdcf05941a4a3ce3720b8066c393b145031ba8f081ee
43118095694 f2d69fc82ed6eaea3daf6481716f1141357a56f49374bc36c37813273465085e
43122643626 5a66f5ead24ffacda97ebdb61ff3e9cd5acfc7413f487f9730fde68011114130
43128946274 8c7604a517fcad9591fe01ec8a203783ed52862547f3a9fd107ccd820b6aef92
43130533897 024f26e4fe5c1b9ce75eb351ab7bd280c8970e52fb9e17b2408c5f26432f5804
43131489422 398ffc55f7f554553be33f1e5d3efd488990c24c711a9c9adee83ddfb54d39d4
43135084402 ade06a25aee60cca744b505f59323fc84b80cd8f230f9bd916a7f1d25e638005
"

if ! command -v cosign >/dev/null; then
  echo "cosign is not on PATH (scripts/install-tools.sh puts it there)"
  exit 1
fi
for d in "$dir" ${kept:+"$kept"}; do
  if [ ! -d "$d" ]; then
    echo "$d is not a directory"
    exit 1
  fi
done

ask() {
  cosign verify-blob "$1" --bundle "$2" --certificate-identity "$SIGNED_BY" \
    --certificate-oidc-issuer "$ISSUER" >/dev/null 2>&1
}

# Everything that reads a record's bytes, in one place and by no other tool.
# -I: the files are data, and nothing beside them is code.
#   run <record>            the run the record says it is of
#   sha256 <file>           its sha256
#   changed <record> <to>   a copy with one byte appended, read back
#   same <a> <b>            the two files are the same bytes
py() {
  python3 -I -c '
import hashlib, json, sys
what, args = sys.argv[1], sys.argv[2:]
if what == "run":
    print(json.load(open(args[0], encoding="utf-8"))["run"]["id"])
elif what == "sha256":
    print(hashlib.sha256(open(args[0], "rb").read()).hexdigest())
elif what == "changed":
    data = open(args[0], "rb").read()
    with open(args[1], "wb") as f:
        f.write(data + b" ")
    sys.exit(0 if open(args[1], "rb").read() == data + b" " else 1)
elif what == "same":
    sys.exit(0 if open(args[0], "rb").read() == open(args[1], "rb").read() else 1)
else:
    sys.exit(2)
' "$@" 2>/dev/null
}

# The sha256 this script carries for a run recorded before the repository was
# public; fails for any other run.
pinned() {
  local id sum
  while read -r id sum; do
    if [ "$id" = "$1" ]; then
      printf '%s\n' "$sum"
      return 0
    fi
  done <<<"$BEFORE_PUBLIC"
  return 1
}

if ! work="$(mktemp -d)"; then
  echo "could not make a directory for the changed copies: nothing was checked"
  exit 1
fi
trap '/bin/rm -rf "$work"' EXIT
signed=0
unsigned=0
held=0
bad=0
for rec in "$dir"/*.json; do
  [ -e "$rec" ] || continue
  case "$rec" in *.sigstore.json) continue ;; esac
  name="${rec##*/}"
  id="${name%.json}"
  case "$id" in
    '' | *[!0-9]*) echo "$name: a record whose name is not a run id"; bad=1; continue ;;
  esac
  inside="$(py run "$rec")" || inside=""
  if [ "$inside" != "$id" ]; then
    echo "$name: the record inside is run ${inside:-nobody}'s, not $id's"
    bad=1
    continue
  fi
  bundle="$rec.sigstore.json"
  if [ ! -f "$bundle" ]; then
    if ! pin="$(pinned "$id")"; then
      echo "$name: a record with no signature, and not one of those made before the repository was public"
      bad=1
    elif [ "$(py sha256 "$rec")" != "$pin" ]; then
      echo "$name: a record made before the repository was public, and not the bytes this script has for it"
      bad=1
    else
      unsigned=$((unsigned + 1))
    fi
    continue
  fi
  signed=$((signed + 1))
  if ! ask "$rec" "$bundle"; then
    echo "$name: cosign does not verify it, with the bundle beside it, as signed by this repository's e2e workflow on main"
    bad=1
    continue
  fi
  # The copy cosign must refuse. If it was not made, a refusal would show
  # nothing.
  /bin/rm -f "$work/changed.json"
  if ! py changed "$rec" "$work/changed.json"; then
    echo "$name: the copy with one byte appended could not be made, so cosign was shown nothing to refuse"
    bad=1
    continue
  fi
  if ask "$work/changed.json" "$bundle"; then
    echo "$name: cosign accepts a copy with one byte appended"
    bad=1
  fi
done

for bundle in "$dir"/*.json.sigstore.json; do
  [ -e "$bundle" ] || continue
  rec="${bundle%.sigstore.json}"
  if [ ! -f "$rec" ]; then
    echo "${rec##*/}: a signature with no record beside it"
    bad=1
  fi
done

if [ -n "$kept" ]; then
  cited=0
  for rec in "$kept"/*.json; do
    [ -e "$rec" ] || continue
    case "$rec" in *.sigstore.json) continue ;; esac
    name="${rec##*/}"
    if [ -f "$rec.sigstore.json" ]; then
      cited=$((cited + 1))
      if ! py same "$rec" "$dir/$name" || ! py same "$rec.sigstore.json" "$dir/$name.sigstore.json"; then
        echo "$name: $kept has this signed record, and $dir does not hold the same two files"
        bad=1
      else
        held=$((held + 1))
      fi
    elif [ -f "$dir/$name" ] && ! py same "$rec" "$dir/$name"; then
      echo "$name: $kept and $dir hold different files under this name"
      bad=1
    fi
  done
  if [ "$cited" -eq 0 ]; then
    echo "no signed record in $kept: $dir was held to nothing"
    exit 1
  fi
fi

if [ "$signed" -eq 0 ]; then
  echo "no signed record in $dir: nothing was checked"
  exit 1
fi
[ "$bad" -eq 0 ] || exit 1
said="$signed signed records in $dir: each is the run its name says, cosign verifies each and refuses a copy of each with one byte appended; $unsigned made before the repository was public carry no signature and have the sha256 this script carries"
if [ -n "$kept" ]; then
  said="$said; the $held signed records of $kept are among them, byte for byte"
fi
echo "$said"
