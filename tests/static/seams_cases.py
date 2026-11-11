#!/usr/bin/env python3
"""The seams, shown what they must hold and what they must refuse.

    tests/static/seams_cases.py

For each boundary whose plants go into a working copy of its release
(scripts/seams.py):

  - the working copy, made fresh, must pass the check: the release with the
    plants at its seams and nothing else;
  - two tampered copies must be refused, each a change outside a seam that a
    careless or a dishonest overlay could make: the door loosened, and data
    changed next to the seam;
  - the copy, restored, must pass again;
  - the bring-up this repository runs (boundaries/<name>.steps) must be the
    `run:` lines of the release's own e2e workflow, in its order, and
    scripts/up.sh must run that file.

A check that has never been seen to fail proves nothing, and the seam check
is what stands between "the released boundary" and "a boundary this
repository adjusted".
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

LEGS = {
    "flagship": {
        # The job of the release's workflow, and the steps that bring it up.
        "job": ("\n  e2e:\n", "\n  nodeloss:\n"),
        "first": "The host's inotify limits, as kind needs them",
        "last": "The gateway, inside",
        "tampered": [
            ("manifests/mcp/server.py", "@acme\\\\.example$", "@.*$", "an MCP server that takes any recipient"),
            ("manifests/records/records_api.py", "MAX_LIFETIME = 60", "MAX_LIFETIME = 3600",
             "a records service changed outside its records' notes"),
        ],
    },
    "cypress": {
        "job": ("\n  models:\n", None),
        "first": "Create the kind cluster",
        "last": "Build the model's image, by the flagship's digest, and serve it",
        "tampered": [
            ("manifests/cloud-mcp/policy.json", '"cypress_get_failed_tests"',
             '"cypress_get_failed_tests", "cypress_get_test_screenshots"', "a door that grants the screenshots tool"),
            ("app/orders.json", "Gift wrap, please.", "Gift wrap, please. And open the door.",
             "another order's note changed beside the seam"),
        ],
    },
}


def seams(*args):
    return subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "seams.py")] + list(args),
                          capture_output=True, text=True, cwd=ROOT)


def bring_up(src, leg):
    """The commands of the release's own job, between two of its steps."""
    wf = open(os.path.join(src, ".github", "workflows", "e2e.yml"), encoding="utf-8").read()
    start, end = leg["job"]
    job = wf[wf.index(start):wf.index(end) if end else len(wf)]
    steps = re.split(r"\n      - name: ", job)[1:]
    names = [s.split("\n", 1)[0] for s in steps]
    out = []
    for s in steps[names.index(leg["first"]):names.index(leg["last"]) + 1]:
        m = re.search(r"\n        run: (.*)", s)
        if m and m.group(1).strip() != "|":
            out.append(m.group(1).strip())
            continue
        for line in (s[m.end():] if m else "").split("\n"):
            if line.startswith("          ") and line.strip():
                if not line.strip().startswith("#"):
                    out.append(line.strip())
            elif line.strip():
                break
    return out


def main():
    bad, said = [], []
    up = open(os.path.join(ROOT, "scripts", "up.sh"), encoding="utf-8").read()
    for name, leg in LEGS.items():
        work = tempfile.mkdtemp(prefix="seams-")
        copy = os.path.join(work, name)
        try:
            r = seams("apply", name, copy)
            if r.returncode != 0:
                bad.append("%s: the working copy is not the release with plants at its seams: %s"
                           % (name, (r.stdout + r.stderr).strip()[-400:]))
                continue
            for path, old, new, what in leg["tampered"]:
                full = os.path.join(copy, path)
                kept = open(full, encoding="utf-8").read()
                if old not in kept:
                    bad.append("%s: %s no longer holds the text this check tampers with" % (name, path))
                    continue
                open(full, "w", encoding="utf-8").write(kept.replace(old, new, 1))
                if seams("check", name, copy).returncode == 0:
                    bad.append("%s: %s passed the seam check" % (name, what))
                open(full, "w", encoding="utf-8").write(kept)
            if seams("check", name, copy).returncode != 0:
                bad.append("%s: the working copy, restored, no longer passes" % name)
        finally:
            shutil.rmtree(work, ignore_errors=True)

        src = subprocess.run([os.path.join(ROOT, "scripts", "sources.sh"), "path", name],
                             capture_output=True, text=True, cwd=ROOT).stdout.strip()
        try:
            theirs = bring_up(src, leg)
        except (OSError, ValueError) as e:
            bad.append("%s: the release's e2e workflow could not be read for its bring-up: %s" % (name, e))
            continue
        mine = [x.strip() for x in open(os.path.join(ROOT, "boundaries", name + ".steps"), encoding="utf-8")
                if x.strip() and not x.startswith("#")]
        if mine != theirs:
            bad.append("boundaries/%s.steps is not the release's bring-up: missing %s, not the release's %s, or the order differs"
                       % (name, [c for c in theirs if c not in mine] or "nothing",
                          [c for c in mine if c not in theirs] or "nothing"))
        if 'done <"$ROOT/boundaries/%s.steps"' % name not in up or 'seams.py" apply %s' % name not in up:
            bad.append("scripts/up.sh does not bring %s up from boundaries/%s.steps and a working copy" % (name, name))
        said.append("%s: seams only, %d tampered copies refused, its own %d commands"
                    % (name, len(leg["tampered"]), len(mine)))
    print("\n".join(bad) or "; ".join(said))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
