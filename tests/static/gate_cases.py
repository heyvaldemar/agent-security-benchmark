#!/usr/bin/env python3
"""The agent at the sandbox's boundary starts behind its wall.

    tests/static/gate_cases.py

The sandbox's release starts its agent only after an init container,
wait-for-the-wall, has seen the agents' resolver answer and the cluster's
CoreDNS not answer. The release's own comments say why: kind's network plugin
learns a new pod's address a moment after the pod starts, and until then no
policy judges the pod's packets. What this repository reads at that boundary
(what the agent tried, what stopped it, what reached the outside) is read as
the wall's doing, so it assumes the agent's first packet leaves a pod that is
already walled in. A release that dropped the gate would change what is
measured, and until this check nothing here would have turned red. Three
things hold it:

  - the pinned release's Job, the one the leg takes, has the gate as its
    first init container, and the gate asks both resolvers and fails when
    the wall never comes;
  - the Job the leg applies is that Job under another name and nothing else:
    the lines of tests/e2e/sandbox.sh that make it are run here on the
    release's file;
  - the Job that admission is shown as its control
    (tests/e2e/plants/the-agent-job-as-run.yaml) is that same Job, comments
    apart.

And gate() is shown the Jobs it must refuse, each for its reason:

    no gate            the release's Job with its init containers taken out
    not first          another init container before the gate
    one resolver       a gate that no longer asks the cluster's CoreDNS, so
                       it passes before any policy has taken hold
    cannot fail        a gate that ends in success when the wall never comes
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GATE = "wait-for-the-wall"
# The agents' own resolver has to answer, and the cluster's CoreDNS, which the
# agents' policy refuses, has to stay silent: the first says the network is
# up, the second that the policy has taken hold. Both addresses are the
# release's.
ASKS_AGENTS_DNS = re.compile(r"(?<!! )nslookup [^;&|]*\b10\.96\.0\.53\b")
REFUSED_BY_CLUSTER_DNS = re.compile(r"! nslookup [^;&|]*\b10\.96\.0\.10\b")
FAILS = re.compile(r"done;.*\bexit 1\s*$", re.M)


def init_containers(doc):
    """The names of a Job's init containers, in order, and each one's text."""
    m = re.search(r"^      initContainers:\n(.*?)(?=^      \S)", doc, re.S | re.M)
    if not m:
        return [], []
    parts = re.split(r"^        - name: ", m.group(1), flags=re.M)[1:]
    return [p.split("\n")[0].strip() for p in parts], parts


def gate(doc):
    """Why this Job's agent could start before its wall stands, or None."""
    names, parts = init_containers(doc)
    if not names:
        return "the Job has no init container: its agent starts before any wall is known to stand"
    if names[0] != GATE:
        return "the first init container is %s, not %s" % (names[0], GATE)
    first = parts[0]
    if not ASKS_AGENTS_DNS.search(first) or not REFUSED_BY_CLUSTER_DNS.search(first):
        return "the gate does not ask both resolvers: the agents' must answer and the cluster's must not"
    if not FAILS.search(first):
        return "the gate cannot fail: a pod whose wall never comes would start its agent"
    return None


def bare(text):
    """A manifest's lines, comments and empty lines apart."""
    return [l for l in text.split("\n") if l.strip() and not l.strip().startswith("#")]


def main():
    bad = []
    src = subprocess.run([os.path.join(ROOT, "scripts", "sources.sh"), "path", "sandbox"],
                         capture_output=True, text=True, cwd=ROOT).stdout.strip()
    tag = next((l.split()[2] for l in open(os.path.join(ROOT, "sources.lock"), encoding="utf-8")
                if l.startswith("sandbox ")), "?")
    try:
        path = os.path.join(src, "manifests", "agent", "job.yaml")
        release = open(path, encoding="utf-8").read().split("\n---\n")[0]
    except OSError as e:
        print("the sandbox release's Job could not be read: %s" % e)
        return 1

    # 1. The release's Job, as pinned.
    why = gate(release)
    if why:
        bad.append("the sandbox release %s, manifests/agent/job.yaml: %s" % (tag, why))

    # 2. The Job the leg applies: its own lines, run on the release's file.
    sh = open(os.path.join(ROOT, "tests", "e2e", "sandbox.sh"), encoding="utf-8").read()
    lines = re.search(r'python3 - "\$SRC/manifests/agent/job\.yaml" "\$name" <<\'PY\' \| kubectl apply -f - >/dev/null\n'
                      r"(.*?)\nPY\n", sh, re.S)
    if not lines:
        bad.append("tests/e2e/sandbox.sh no longer makes its Job from the release's manifests/agent/job.yaml "
                   "and applies it: this check cannot see what the leg runs")
    else:
        r = subprocess.run([sys.executable, "-", path, "asb-check"], input=lines.group(1),
                           capture_output=True, text=True, cwd=ROOT)
        applied = r.stdout
        why = gate(applied) if r.returncode == 0 else "the leg's own lines fail on the release's file"
        if why:
            bad.append("the Job the leg applies: %s" % why)
        elif applied.rstrip("\n") != release.replace("agent-demo", "asb-check").rstrip("\n"):
            bad.append("the Job the leg applies is not the release's Job under another name: something else differs")

    # 3. The Job admission is shown as its control.
    shown = open(os.path.join(ROOT, "tests", "e2e", "plants", "the-agent-job-as-run.yaml"), encoding="utf-8").read()
    if bare(shown) != bare(release.replace("agent-demo", "asb-plant")):
        bad.append("tests/e2e/plants/the-agent-job-as-run.yaml is not the release's Job under the name asb-plant: "
                   "admission is shown a Job the leg does not run")

    # 4. gate() itself, shown what it must refuse.
    block = re.search(r"^      initContainers:\n.*?(?=^      \S)", release, re.S | re.M)
    cases = []
    if block:
        other = "        - name: something-first\n          image: busybox\n"
        cases = [
            ("no gate", release.replace(block.group(0), ""), "has no init container"),
            ("not first", release.replace("      initContainers:\n", "      initContainers:\n" + other),
             "the first init container is something-first"),
            ("one resolver", re.sub(r" && ! nslookup [^;]*", "", release), "does not ask both resolvers"),
            ("cannot fail", re.sub(r"exit 1(\s*\n          resources:)", r"exit 0\1", release), "cannot fail"),
        ]
    for name, doc, reason in cases:
        why = gate(doc)
        if doc == release:
            bad.append("case %s: the release's Job has nothing for it to change" % name)
        elif why is None:
            bad.append("case %s: accepted" % name)
        elif reason not in why:
            bad.append("case %s: refused, and not for its reason (%r): %s" % (name, reason, why))

    if bad:
        print("\n".join(bad))
        return 1
    print("the sandbox's agent Job (%s) starts its agent behind %s, the leg applies that Job under another name "
          "and nothing else, and %d Jobs without a working gate are refused, each for its reason" % (tag, GATE, len(cases)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
