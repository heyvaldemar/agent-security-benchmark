# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

<!-- conformance: first release not before 2026-11-25 - the legs with open models and two green scheduled runs come first -->

## [Unreleased]

### Added

- The suite: six dressings of a planted instruction, each taken from a repository that already plants it, in `suite/suite.json`, bound to three boundaries in `boundaries/` and rendered by `scripts/render.py`, whose `check` holds every boundary to the same six ([ADR 1](docs/decisions/0001-one-planted-suite-through-every-boundary.md)).
- `sources.lock` and `scripts/sources.sh`: each boundary is a release of its repository, read only after its sha256, its cosign signature and its SLSA provenance have passed.
- The leg at the sandbox's boundary (`tests/e2e/sandbox.sh`): the release brought up by its own scripts, a model's namespace and an outside address beside it, the release's own agent Job carrying this repository's agent in its ConfigMap ([ADR 2](docs/decisions/0002-a-model-beside-the-sandbox.md)).
- Two models without weights, `obedient` and `deaf`, and a door planted open: the reader of results is shown both ends of its scale and the failure its zero exists to catch, on every run ([ADR 3](docs/decisions/0003-two-models-without-weights.md)).
- `scripts/read.py`: what a model did, from the agent's calls, and what the boundary let out, from the outside's log and the door's audit, with a control for every zero.
- `scripts/validate.sh`, eight static checks, each shown its planted violations (`tests/static/plants.tsv`), and four recorded legs whose answer is known (`tests/static/fixtures/`).

### Found while building it

- cypress-cloud-triage-agent v1.0.0 holds its scripted agent only. The model leg this benchmark needs is on that repository's main and in no release, so the suite is bound for that boundary and no leg runs it yet.
- kubernetes-llm-inference-gateway holds no tool and no identity: nothing an agent acts through. It is not a boundary in this benchmark's sense and gets no row.
- The flagship's agent offers a model only the tools its MCP server lists, so a plant cannot ask it for a tool that was not granted. That ask is not bound there, and its cell is empty by design, not a refusal.
