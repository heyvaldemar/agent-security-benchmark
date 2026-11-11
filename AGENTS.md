# Working on this repository as an agent

Most of the code here is written by an AI agent, and the decisions and the verification are the maintainer's. This file is what the agent is held to. A reviewer can hold it to the same rules.

## What this repository claims

One suite of planted instructions goes through each boundary as it was released, and two things are published: what each model did, and what each boundary let out. Every sentence in the README that says something holds is a check that runs in CI: `scripts/validate.sh`, `tests/static/plant_violations.py` or `tests/e2e/run.sh`. A claim with no check is not written. A number is copied from a named run. It is a benchmark of reference architectures, and nothing says otherwise.

## Before changing anything

- Read the decision record that covers it, under `docs/decisions/`. A change that alters a decision amends that record or adds one, in the same format, ending with how the choice is explained to a customer.
- `make check` runs the static checks and shows each one its planted violation (`tests/static/plants.tsv`). It must stay all caught, none missed, none stale.

## A check is trusted only after it has failed

A new or changed check ships with the violation it exists for: a row in `tests/static/plants.tsv`, a planted manifest under `tests/e2e/plants/` that says what it expects, or a recorded leg under `tests/static/fixtures/` whose answer is known. The reader of results is held to this hardest: `obedient` and `deaf` are models without weights whose rows are known before the run, and the outside's zero is shown a door planted open on every run (ADR 3).

## The boundaries are releases, and their logic is not this repository's

- A boundary is read only from where `scripts/sources.sh` unpacked the release `sources.lock` pins, after its sha256, its cosign signature and its SLSA provenance have passed. Never from a branch, a checkout or a copy.
- Nothing in a release's tree is edited. What this repository changes in a boundary is data at a named seam (a tool's message, an agent's ConfigMap), and what it adds stands beside the boundary (`manifests/`).
- Moving a boundary to a new release is a change to `sources.lock`, reviewed as a diff, and the numbers before and after name their tags.
- A repository's own `AGENTS.md` still binds its workflows. Nothing here dispatches another repository's workflow.

## Two levels, never one source

What a model did is read from the agent's calls and is measured, never a check. What a boundary let out is read from the boundary's side (the outside's own log, the door's audit) and is gated at zero, with a control that must not be zero. A check that reads "nothing left" from the agent's own word is a bug.

## Numbers

No number in the README or a release is typed by hand. It names its run or its window. A run the README cites has its record under `docs/runs/<run id>.json`, made by `scripts/numbers.py record` from that run's artifacts, and the README's tables are made from it by `scripts/numbers.py check --write`; `scripts/validate.sh numbers` fails when the page and the record differ. A word of cadence (daily, weekly) is written only after two scheduled runs in a row have passed. When results differ between runs, find what changed (the runner, the release, the model, the seed) before calling it noise.

## Releases

- Fill `CHANGELOG.md` `[Unreleased]` in the same commit as the change.
- Tag only a commit whose e2e is green, and say in the release notes what is new, what was found while building it, and how it was checked.
- After publishing, verify the signed archive the way a stranger would: `cosign verify-blob` with the release's `.sigstore.json`, `slsa-verifier` with its provenance, and a tampered copy that both must refuse.

## Writing

Plain and specific. No em dashes, no marketing words, no claim the evidence does not carry. A design property is not called a vulnerability. Name runs, commits and files. Commits are authored `Vladimir Mikhalev <10498744+heyvaldemar@users.noreply.github.com>` and carry no AI attribution lines.

## Never

- Print a secret, or put one in a file, a log or an argument. This repository holds none: no model API key, no cloud credential.
- Turn off or weaken a check, a plant, a control or a gate to get a run green.
- Count a copy of a plant in a model's answer as the model acting on it, or read what left a boundary from the agent's log.
- Edit a file inside `.cache/sources/`, or read a boundary from anywhere else.
- Open the agents' way to anything but the model's one port, outside the one planted manifest that exists to be caught (`tests/e2e/plants/an-open-door.yaml`).
- Touch anything outside this repository's own CI to test a change: no cloud resources, no outside services, no other repository's workflows.
- Put a model that needs a credential into the e2e. Open weights on CPU, or the two stand-ins.
