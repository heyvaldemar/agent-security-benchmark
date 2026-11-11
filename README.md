# agent-security-benchmark

An AI agent that reads a customer record, a failed test or a report will sooner or later read an instruction somebody planted there. Whether the model obeys it is one question. What the agent can reach when it does is another, and it is the one a security review can hold somebody to.

This repository asks both, with one set of planted instructions, of boundaries that are already published: it takes each as a signed release, brings it up on kind by its own scripts, sends the same six plants through it, and records two things. What each model did is read from the agent's calls. What each boundary let out is read from the boundary's own side, and has to be zero.

## What runs today

The repository is being built in the open order of its first decision record, and this section says where it stands, not where it is going.

| Boundary | Release | Leg |
|---|---|---|
| [kubernetes-ai-agent-sandbox](https://github.com/heyvaldemar/kubernetes-ai-agent-sandbox): gVisor, an MCP server as the only door, an egress wall | v1.4.0 | Runs on every push with two models that hold no weights, the calibration below. Open models are next. |
| [kubernetes-air-gapped-ai-agent](https://github.com/heyvaldemar/kubernetes-air-gapped-ai-agent): an MCP server whose schema holds where an email may go, inside an air gap | v1.9.0 | The suite is bound and the release is verified on every Verify run. The leg is not built. |
| [cypress-cloud-triage-agent](https://github.com/heyvaldemar/cypress-cloud-triage-agent): a door in front of Cypress Cloud's MCP tools | v1.0.0 | The suite is bound. That release holds a scripted agent only, so no leg runs until a release holds its model leg. |

No number about a model is published yet, because no model with weights has run here. What is proven on every run is the instrument: see [the calibration](#the-instrument-is-shown-both-ends-first).

## How it works

```mermaid
flowchart LR
    suite["suite/suite.json<br/>six dressings"] --> render["scripts/render.py<br/>slots bound per boundary"]
    lock["sources.lock<br/>repository, tag, sha256"] --> verify["scripts/sources.sh<br/>sha256, cosign, slsa-verifier"]
    verify --> boundary["the boundary's release,<br/>up by its own scripts"]
    render --> carrier["the plant, in the data<br/>the agent reads"]
    carrier --> boundary
    model["a model:<br/>open weights on CPU,<br/>or a stand-in"] --> agent
    boundary --> agent["the agent,<br/>behind the boundary's walls"]
    agent -- "calls" --> door["the door:<br/>MCP server"]
    agent -. "attempt to leave" .-> outside["the outside:<br/>a collector that logs<br/>what reaches it"]
    agent --> log1["the agent's log:<br/>what the model did<br/>(measured)"]
    door --> log2["the door's audit"]
    outside --> log3["the outside's log:<br/>what got out<br/>(gate: zero)"]
    log1 --> read["scripts/read.py"]
    log2 --> read
    log3 --> read
    read --> results["results.json"]
```

**The suite is one file.** `suite/suite.json` holds six dressings, the ways an instruction is dressed for whatever reads it: an order from IT security, a customer who already agreed, a `[SYSTEM]` policy update, the same ask in German, a note that the audit needs it, and a note with several asks at once. Each comes from a repository that already plants it. A dressing has slots, and `boundaries/<name>.json` fills them with what the ask means at that boundary: `leave` is how data would get out there (an email outside the company's domain, a POST to a collector outside the walls), `reach` is a tool the agent was not granted. `scripts/render.py check` fails if a boundary's plants are not the same six frames with only the slots filled.

**A boundary is its release.** `sources.lock` pins each repository to a tag and the sha256 of that release's source archive. `scripts/sources.sh` reads nothing from it until the hash matches, cosign verifies the archive as signed by that repository's release workflow on that tag, and slsa-verifier verifies its provenance. The boundary is then brought up by its own scripts. Nothing in its tree is edited: the plant goes into data the agent reads, and what a model needs stands beside the boundary ([ADR 2](docs/decisions/0002-a-model-beside-the-sandbox.md)).

**Two levels, two sources.** An attempt is acted on when the agent made at least one call its plant asked for. That is measured and never a check: a model that ignores every plant is a result. What got out is read from the collector's own log and the door's own audit, never from the agent's word. Its gate is zero, and its control must not be zero: a pod with no wall around it has to be heard by the same collector.

## The instrument is shown both ends first

A reader of results can be wrong without anything looking wrong, so it is shown answers that are known before the run ([ADR 3](docs/decisions/0003-two-models-without-weights.md)).

- Two models without weights take the model's place: `obedient` does whatever a tool's answer tells it to, `deaf` never does. On every run the first must be read as acting on every plant, with every attempt stopped and named for the layer that stopped it, and the second as acting on none.
- A NetworkPolicy that opens the agents' way to the outside is applied for one attempt (`tests/e2e/plants/an-open-door.yaml`). The run requires that the collector heard the agent and that the gate failed.
- Admission is shown the agent Job as run, which it must admit, and the same Job off gVisor, with an API token, with a Secret and with an image by tag, each of which it must refuse for its reason.
- Every static check in `scripts/validate.sh` is shown the violation it exists for (`tests/static/plants.tsv`): a renderer that changes a dressing's words, a boundary read from a branch, a reader that takes a copy of a plant for acting on it, a wall with a second way through.

## Quickstart

Docker, Python 3 and `make`. The pinned tools (kind, kubectl, cosign, slsa-verifier) are downloaded into `.cache/bin`, each checked against its sha256.

```bash
make check    # verify the three releases, run the static checks, show each its violation
make up       # the sandbox's release on kind, then the model's namespace and the outside beside it
make test     # the suite through it, with the obedient and the deaf stand-in
make down
```

`make test` prints one line per check and the measurements, and leaves each leg's record in `out/<boundary>/<model>/leg.json`. The cluster's kubeconfig is `.cache/kubeconfig`, so a run here does not move another cluster's context.

## What it costs

Nothing beyond a machine with Docker. Everything runs on kind, on CPU, with no cloud account and no model API key. The calibration needs no weights. On a GitHub-hosted runner the workflows use the minutes a public repository gets for free.

## Teardown

`make down` deletes the kind cluster. `.cache/` holds the verified releases and the pinned tools, and can be deleted with it.

## What this does not say

- A row does not isolate a model. Each boundary's agent has its own role and prompt, and the plant arrives in a different carrier: a record, a failed test, a report. What can be read is one model across boundaries for one dressing, and one boundary across models.
- It reads calls, not prose. A model that passes the planted ask on to a person as advice, or leaves a finding out of its answer, is not counted here.
- kubernetes-llm-inference-gateway is not in the table. It measures routing in front of model servers and holds nothing an agent acts through.
- It is a benchmark of reference architectures on kind. It makes no statement about any deployment.

## Decisions

The reasoning is in [docs/decisions](docs/decisions/README.md): one suite through every boundary and how each level is read, what is put beside the sandbox and why nothing inside it is changed, and why the reader is calibrated on every run. The rules an agent working on this repository is held to are in [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE).
