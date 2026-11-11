#!/usr/bin/env bash
# sources.sh NAME... - fetch the release sources.lock pins for each named
# boundary, verify it as a stranger would, and unpack it into
# .cache/sources/NAME/src.
#
# Three checks, each of which refuses the archive on its own: the sha256
# pinned in sources.lock; cosign verify-blob against the release's Sigstore
# bundle, with the exact identity of that repository's release workflow on
# that tag; slsa-verifier against the release's provenance, for that tag.
# Nothing from a boundary is read before all three pass.
#
#   sources.sh path NAME    prints where NAME is unpacked, verifying first
#                           if it is not there yet
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="${SOURCES_LOCK:-$ROOT/sources.lock}"
CACHE="${SOURCES_CACHE:-$ROOT/.cache/sources}"
say() { printf '== %s\n' "$*" >&2; }
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

fetch() {
  local name="$1" repo tag sha
  read -r repo tag sha < <(awk -v n="$name" '$1 == n && $0 !~ /^[[:space:]]*#/ {print $2, $3, $4}' "$LOCK" | head -n 1)
  [ -n "${repo:-}" ] && [ -n "${sha:-}" ] || { echo "sources.lock names no boundary '$name'" >&2; exit 1; }
  local file="${repo#*/}-$tag" out="$CACHE/$name"
  local base="https://github.com/$repo/releases/download/$tag"
  mkdir -p "$out/release"
  for f in "$file.tar.gz" "$file.tar.gz.sigstore.json" "$file.intoto.jsonl"; do
    [ -s "$out/release/$f" ] || curl -fsSL --retry 3 -o "$out/release/$f" "$base/$f"
  done
  local got
  got="$(sha256 "$out/release/$file.tar.gz")"
  [ "$got" = "$sha" ] || { echo "$file.tar.gz is $got; sources.lock pins $sha" >&2; exit 1; }
  cosign verify-blob "$out/release/$file.tar.gz" --bundle "$out/release/$file.tar.gz.sigstore.json" \
    --certificate-identity "https://github.com/$repo/.github/workflows/release-assets.yml@refs/tags/$tag" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null 2>&1 \
    || { echo "cosign does not verify $file.tar.gz as signed by $repo's release workflow on $tag" >&2; exit 1; }
  slsa-verifier verify-artifact "$out/release/$file.tar.gz" --provenance-path "$out/release/$file.intoto.jsonl" \
    --source-uri "github.com/$repo" --source-tag "$tag" >/dev/null 2>&1 \
    || { echo "slsa-verifier does not verify $file.tar.gz's provenance for $repo at $tag" >&2; exit 1; }
  rm -rf "$out/src" && mkdir -p "$out/src"
  tar -xzf "$out/release/$file.tar.gz" -C "$out/src" --strip-components 1
  printf '%s %s %s\n' "$repo" "$tag" "$sha" >"$out/verified"
  say "$repo $tag: sha256 pinned, signature and provenance verified, unpacked into .cache/sources/$name/src"
}

# Verified already, for the line the lock holds now: a changed lock line is a
# different release, and is verified again before anything reads it.
fresh() {
  local name="$1" line
  line="$(awk -v n="$name" '$1 == n && $0 !~ /^[[:space:]]*#/ {print $2, $3, $4}' "$LOCK" | head -n 1)"
  [ -d "$CACHE/$name/src" ] && [ "$(cat "$CACHE/$name/verified" 2>/dev/null)" = "$line" ]
}

if [ "${1:-}" = path ]; then
  name="${2:?usage: sources.sh path NAME}"
  fresh "$name" || fetch "$name"
  printf '%s\n' "$CACHE/$name/src"
  exit 0
fi
[ $# -gt 0 ] || { echo "usage: sources.sh NAME... | sources.sh path NAME" >&2; exit 2; }
for name in "$@"; do fetch "$name"; done
