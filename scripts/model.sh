#!/usr/bin/env bash
# model.sh - an open model's weights for a boundary that serves none of its
# own (the sandbox), by the flagship's pins.
#
#   model.sh fetch MODEL   the publisher's file at the revision the flagship's
#                          models/models.lock pins, refused unless its sha256
#                          is the one that lock pins
#   model.sh load MODEL    the file as an image of one file, loaded into the
#                          kind node
#   model.sh serve MODEL   llama-server in the models namespace with that
#                          image as a read-only volume, in the stand-in's
#                          place: the same Service, the same walls
#   model.sh line MODEL    the lock line, for a run's record
#
# The lock is read from the flagship's verified release (scripts/sources.sh),
# never copied here: a copy would be a second list of models to keep true.
# The image is built locally and named by the file's sha256; what pins the
# bytes the model server reads is the check inside its pod, which hashes the
# mounted file and refuses to start on any other (manifests/sandbox/llama.yaml).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${MODEL_CACHE:-$ROOT/.cache/models}"
CLUSTER="${KIND_CLUSTER:-agent-sandbox}"
cmd="${1:-}"
MODEL="${2:-}"
[ -n "$cmd" ] && [ -n "$MODEL" ] || { echo "usage: model.sh fetch|load|serve|line MODEL" >&2; exit 2; }
say() { printf '== %s\n' "$*" >&2; }
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

FLAGSHIP="$("$ROOT/scripts/sources.sh" path flagship)"
read -r name url sha license _ < <(awk -v m="$MODEL" '$1 == m && $0 !~ /^[[:space:]]*#/' "$FLAGSHIP/models/models.lock" | head -n 1) || true
[ "${name:-}" = "$MODEL" ] || { echo "the flagship's models.lock pins no model '$MODEL'" >&2; exit 1; }
IMAGE="asb-model/$MODEL:${sha:0:12}"

case "$cmd" in
  line)
    printf '%s %s %s %s\n' "$name" "$url" "$sha" "$license"
    ;;
  fetch)
    mkdir -p "$CACHE"
    if [ ! -s "$CACHE/$MODEL.gguf" ] || [ "$(sha256 "$CACHE/$MODEL.gguf")" != "$sha" ]; then
      curl -fsSL --retry 3 -o "$CACHE/$MODEL.gguf" "$url"
    fi
    got="$(sha256 "$CACHE/$MODEL.gguf")"
    [ "$got" = "$sha" ] || { echo "$MODEL.gguf is $got; the flagship's models.lock pins $sha" >&2; exit 1; }
    say "$MODEL: the publisher's file, sha256 ${sha:0:12}, licence $license"
    ;;
  load)
    [ -s "$CACHE/$MODEL.gguf" ] || { echo "run model.sh fetch $MODEL first" >&2; exit 1; }
    dir="$(mktemp -d)"
    trap '/bin/rm -rf "$dir"' EXIT
    ln "$CACHE/$MODEL.gguf" "$dir/model.gguf" 2>/dev/null || /bin/cp -f "$CACHE/$MODEL.gguf" "$dir/model.gguf"
    printf 'FROM scratch\nCOPY model.gguf /model.gguf\n' >"$dir/Dockerfile"
    docker build -q -t "$IMAGE" "$dir" >/dev/null
    kind load docker-image "$IMAGE" --name "$CLUSTER" >/dev/null
    say "$MODEL: loaded into the node as $IMAGE"
    ;;
  serve)
    sed -e "s#@MODEL_IMAGE@#docker.io/$IMAGE#" -e "s#@MODEL_SHA256@#$sha#" -e "s#@ALIAS@#$MODEL#" \
      "$ROOT/manifests/sandbox/llama.yaml" | kubectl apply -f - >/dev/null
    kubectl -n models rollout status deployment/llama --timeout=600s >/dev/null
    say "$MODEL: served by llama-server in the models namespace"
    ;;
  *)
    echo "usage: model.sh fetch|load|serve|line MODEL" >&2
    exit 2
    ;;
esac
