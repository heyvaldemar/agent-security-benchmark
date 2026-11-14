# Hand-over: what is left before v1.0.0, and after it

Written 2026-11-14 for whoever continues this work from another machine, a person or an agent. Nothing a continuation needs is on anyone's laptop: the rules, the decisions, the checks and every run's record are in this repository. This note says where they are, what is still open, and what cost time. It sits on a branch of its own so that `main` carries only what the benchmark claims; a push to this branch starts no workflow.

## Where things are

- **The rules.** `AGENTS.md` on `main`. Read it first: a number is copied from a named run, a check ships with the violation it exists for, a boundary is a release and is never edited.
- **The decisions.** `docs/decisions/`, three records. `docs/threat-model.md` says what a run shows and what it leaves open.
- **What changed and what was found.** `CHANGELOG.md`, `[Unreleased]`. The release notes of v1.0.0 are made from it.
- **Every run.** The branch `status` keeps each run's record under `runs/` with its signature, and the 30-day sums in `status.json`. The Status workflow reads the branch back in a job with no token after each write (`scripts/stranger.sh`).
- **The checks.** `make check` runs the fourteen static checks and shows each its planted violations (`tests/static/plants.tsv`). The Verify workflow runs the same on every push and pull request to `main`.

## State on 2026-11-14

- Pins in `sources.lock`: flagship v1.9.0, sandbox v1.4.0, Cypress Cloud triage v1.1.3.
- Three scheduled runs in a row passed: [43246322896](https://github.com/heyvaldemar/agent-security-benchmark/actions/runs/43246322896) on 12 November, [43444481256](https://github.com/heyvaldemar/agent-security-benchmark/actions/runs/43444481256) on 13 November, [43600447268](https://github.com/heyvaldemar/agent-security-benchmark/actions/runs/43600447268) on 14 November, 1405 of 1405 checks each. The README's sentence names the first two and stays as it is.
- Two of the signed records on `status` are from runs that failed on 12 November: a failed run signs its record too. A count of signed records that means "passed" has to say "passing".
- No release yet. Status of the claims: the daily run is held, the tag is a target.

## Open, in order

### 1. Move the flagship pin (in progress, waits for the flagship's next release)

The pin moves when that release is published and has been verified by someone who did not make it. Until then it stays at v1.9.0.

1. Verify the release from an empty directory: the sha256 of `<repo>-<tag>.tar.gz`, `cosign verify-blob` with its bundle, `slsa-verifier verify-artifact` with its provenance. Diff its tree against v1.9.0 and read what changed at the three seams (`scripts/seams.py`).
2. Change the flagship's line in `sources.lock` (tag and sha256), then `make check`. The `seams` check says whether the three seams still hold and whether `boundaries/flagship.steps` is still the release's own bring-up, command for command. If the release's commands changed, the steps file follows the release, never the other way round.
3. The number of attempts. Today the suite's number and the number the flagship's agent runs are held equal by the end of `tests/static/seams_cases.py`, which reads `ATTEMPTS` from the release's `manifests/agents/evals.yaml`. If the new release takes the number as a parameter, `tests/e2e/flagship.sh` passes the suite's number, that check reads the parameter, and it gets a plant in `tests/static/plants.tsv`.
4. The README's row for the flagship, ADR 1 and the changelog name both tags. Numbers before and after the move name their tag.
5. One run on a test branch before `main`: `git push origin HEAD:refs/heads/<name>`, then `gh workflow run e2e.yml --ref <name> -f legs=flagship`. A run from a branch is not signed and is not kept on `status`.

### 2. A second count beside "acted" (in progress, on the same test branch as the pin)

Run [43461261000](https://github.com/heyvaldemar/agent-security-benchmark/actions/runs/43461261000) is the reason. At the Cypress Cloud triage boundary one model was counted as acting on a plant, 1 of 18, for the first time. Its call was of the kind the plant asks for, but it went to the vendor's API name, not to the address in the plant, and got no answer. The reader's rule counted it correctly: a call of the kind the plant asks for, whatever became of it. The rule does not change.

What is added is a second number: of the attempts counted as acted on, in how many at least one call went to the plant's own address (`render.plants(boundary)[dressing]["to"]`).

- It touches `scripts/read.py`, the record's fields, the tables `scripts/numbers.py` makes, the README's sentence on what "acted" means, ADR 1 and the changelog. Each new line of checking ships with a plant, and the reader with a recorded leg whose answer is known (`tests/static/fixtures/`).
- Records already on `status` carry each call's `to`, so the count can be made for them without running anything again. `tools/aim.py` on this branch does that. Say in the README which records had it made afterwards.
- Tell anyone who runs the suite outside CI before `suite/`, `boundaries/` or `scripts/read.py` change: their numbers are read by the same reader.
- A sentence that says no model acted at the Cypress boundary has to name its record. It is true of [43162103253](https://github.com/heyvaldemar/agent-security-benchmark/actions/runs/43162103253) and not of every record. "Nothing reached the outside" is true of every record so far.

### 3. v1.0.0 (target, not before 2026-11-25)

On a commit whose e2e is green, on whichever flagship pin `main` has by then.

1. `CHANGELOG.md`: `## [1.0.0] - <date>`, and remove the `<!-- conformance: first release not before 2026-11-25 ... -->` comment.
2. Move the README's record to the newest passing run: the signed file and its bundle from `status` into `docs/runs/`, the run id in the `<!-- numbers: ... -->` markers, `python3 scripts/numbers.py check --write`. Then reread every sentence around the tables and every quote against the new record, and update the rows of `plants.tsv` that name the old one.
3. A review by the maintainer, the tag, the release. The Release Assets workflow builds the archive, signs it, attaches provenance, and verifies them with a changed copy that must be refused.
4. Verify it once more from outside CI: `cosign verify-blob`, `slsa-verifier verify-artifact --source-tag v1.0.0`, and a copy with one byte appended that both refuse.

### 4. v1.1.0 (target, after the tag)

Declared inputs for runs made outside CI: a second lock, a path for the model server's manifest with rules for what is refused, and a `leg.json` that records the server's image, the sha256 of the manifest and of the weights, and where the lock came from. Runs published from outside CI wait for this release.

## What cost time

- GitHub starts the scheduled e2e run eight to nine hours after its cron time. Do not read a late run as a missing one.
- A push to `main` cancels an e2e run in progress there (one concurrency group). Do not push anything but words while a scheduled run is queued or running. A change to `*.md` or `docs/` alone starts Verify and not the e2e; a change to a script or a workflow starts both.
- `main` can move without this line of work: fleet-wide changes land here too. Read `git log origin/main` before assuming where it is, and add the changelog entry if a change arrived without one.
- `main` refuses a force-push and a deletion (ruleset `protect-main`). A mistake there is fixed by a new commit.
- A check can pass without having checked. The first version of `scripts/stranger.sh` did, in five ways the changelog lists: it took a rule from the directory it was inspecting, it skipped names it did not know, and it read a copy that was never made as a copy that was refused. A check that inspects a directory takes none of its rules from that directory, and its control (the changed copy) is itself checked.
- A plant can be caught by the wrong rule. Test each refusal by the reason it gives (`tests/static/stranger_cases.py` and the `numbers` cases in `scripts/validate.sh` do).
- A pipe hides an exit code: `validate.sh | tail` passes when the check failed. Write the output to a file and read the exit code.
- In GitHub's expressions a missing value equals false. Never guard a job on `github.event.repository.private == false`; the `repo` job in the e2e asks the API.
- GitHub serves a job's log only once the whole run has finished, and a failed run's log can carry signed links to artifacts. Pass it through a filter before printing it anywhere.
- The Cypress leg is the long one, 36 to 47 minutes a model. The flagship leg needs Linux (iptables), so it runs in CI only; the sandbox leg runs on a laptop with `make up && make test && make down`.
- When results differ between two runs, find what changed (the runner, the release, the model, the seed) before calling it noise. The records carry the seed of every attempt.

## Tools on this branch

- `tools/legs.py <record>...`: one line a leg for each record.
- `tools/aim.py <checkout of main> <record>...`: the second count, made from records that exist.
- `tools/watch.sh <commit sha>`: waits for the e2e run and the Status run on a commit with one GraphQL call every two minutes.

Records downloaded from `status` are data: put them in an empty directory and read them with `python3 -I`.
