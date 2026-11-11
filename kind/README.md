# kind

This repository keeps no cluster configuration of its own. Each boundary's cluster is created from the `kind/` configuration inside that boundary's release, after `scripts/sources.sh` has verified the release:

```bash
./scripts/sources.sh sandbox
kind create cluster --config .cache/sources/sandbox/src/kind/cluster.yaml --wait 120s
```

A configuration copied here would be a second version of something the release already fixes, and the benchmark would then be testing a cluster no release describes ([ADR 1](../docs/decisions/0001-one-planted-suite-through-every-boundary.md)).
