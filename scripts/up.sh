#!/usr/bin/env bash
# up.sh - bring a boundary up on kind the way its own repository does, from
# the release sources.lock pins, and then add what this repository puts
# beside it. Two steps, so the release's own checks can run in between, on
# the release alone.
#
#   up.sh sandbox          kind from the release's kind/cluster.yaml (unless
#                          the cluster is there already), then gVisor and the
#                          sandbox by the release's own scripts
#   up.sh beside sandbox   manifests/: the model's namespace, the outside, and
#                          the agents' one way to the model
#   up.sh down NAME        delete the kind cluster NAME
#
# Nothing in the release's tree is edited. KUBECONFIG is honoured, so a run
# beside other clusters can keep a file of its own.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
say() { printf '== %s\n' "$*"; }

case "${1:-}" in
  sandbox)
    src="$("$ROOT/scripts/sources.sh" path sandbox)"
    if ! kind get clusters 2>/dev/null | grep -qx agent-sandbox; then
      kind create cluster --config "$src/kind/cluster.yaml" --wait 120s
    fi
    (cd "$src" && ./scripts/install-gvisor.sh && ./scripts/install-sandbox.sh)
    say "the sandbox's release is up, as released"
    ;;
  beside)
    [ "${2:-}" = sandbox ] || { echo "usage: up.sh beside sandbox" >&2; exit 2; }
    kubectl apply -k "$ROOT/manifests" >/dev/null
    kubectl -n outside rollout status deployment/collector --timeout=180s >/dev/null
    kubectl -n models rollout status deployment/llama --timeout=180s >/dev/null
    say "beside it: the model's namespace, the outside, and the agents' one way to the model"
    ;;
  down)
    kind delete cluster --name "${2:?usage: up.sh down NAME}"
    ;;
  *)
    echo "usage: up.sh sandbox | up.sh beside sandbox | up.sh down NAME" >&2
    exit 2
    ;;
esac
