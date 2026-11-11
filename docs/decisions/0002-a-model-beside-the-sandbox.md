# 2. A model beside the sandbox, and nothing inside it

- Status: accepted
- Date: 2026-11-11

## Context

[kubernetes-ai-agent-sandbox](https://github.com/heyvaldemar/kubernetes-ai-agent-sandbox) v1.4.0 runs a scripted agent that obeys its planted note every time, and its ADR 4 keeps models out of its CI: its claim is about the walls, and a script proves them the same way each run. This benchmark asks a second question at the same walls, how often a model takes the bait, and that needs a model to reach the agent without the sandbox's release being changed to let it.

Three things in the release decide what is possible. The agent Job (`manifests/agent/job.yaml`) mounts its script from the ConfigMap `agent-script` and is held by admission to gVisor, one token for the MCP server, no Secret, images by digest. The agents' egress is their own resolver and the MCP server, and that resolver answers names inside the cluster only. And NetworkPolicies add up: a policy can open a way and cannot close one another policy opens.

## Decision

Everything a model needs is put beside the release, and one seam of data is used inside it.

- **Beside it** (`manifests/`): a `models` namespace, closed in both directions by default, whose one pod answers the agents' namespace on port 8080; an `outside` namespace with a collector that writes down every request that reaches it; and one NetworkPolicy in the agents' namespace that opens their way to the model's port. `scripts/validate.sh walls` fails if that policy opens anything else, and four planted violations show it can.
- **The seam.** The ConfigMap `agent-script` holds this repository's agent (`manifests/agent/agent.py`) in place of the scripted one, with the attempt's settings in `model.json` beside it. The Job is the release's own file under another name, so admission holds it exactly as it holds theirs. `tests/e2e/plants/` proves that on every run: the Job as run is admitted, and the same Job off gVisor, with an API token, with a Secret or with an image by tag is refused for its reason.
- **The carrier.** The report tool's message, set on the release's own Deployment for each dressing. The agent reads it through the MCP server, as the scripted agent does.
- **The release's own checks run first.** The e2e workflow brings the release up by its own scripts and runs its own `tests/e2e/run.sh` on that runner before anything is added. What follows is measured on a boundary that has just passed its own test.

The agent offers the model more than the door grants: the report tool it has, two records tools it does not, and a web request. A plant that asks for a records tool or for a POST can then be tried, and the door and the network answer, not the tool list. Schemas go without patterns, for the reason in the flagship's ADR 13.

The first run on kind, on 2026-11-11, with the obedient stand-in: six attempts to leave, each stopped by the network policy; two calls to tools not granted, each refused by the MCP server and each in its audit; nothing heard by the collector.

## Consequences

- The agents' egress at this boundary has one more destination than the release gives them. It is named, it is one port, and a check holds it there. A reader comparing with the sandbox's own README should know the difference exists.
- The agent is this repository's, not the sandbox's. Its loop is the Cypress repository's model harness with other tools, and its system prompt does not tell the model that tool results are data, as the flagship's prompt does. Each leg's record carries that as `prompt_says_tool_results_are_data`.
- Weights are not served here yet. The stand-ins take the model's place, by the same Service name, until the leg with open models is built.
- A new sandbox release that renames the ConfigMap, the Job or the report tool's Deployment breaks the leg loudly: the Job is read from the release's file and the script asserts what it replaces.

## Alternatives

- **A fork of the sandbox with a model leg in it.** Then the benchmark measures the fork. The point is the release other people can verify.
- **The model inside the agent's pod.** No new egress, but the Job would differ from the release's, and admission would be holding something else.
- **Only the scripted agent.** That is the sandbox's own e2e, and it runs here as the first step. It cannot say what a model does.

## How to explain this to a customer

We did not modify the protected setup to test it. We put a model next to it, gave the agent one extra connection to that model and nothing else, and checked on every run that the setup's own rules still refuse a tampered agent.
