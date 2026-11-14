#!/usr/bin/env python3
"""scripts/stranger.sh, shown the directories it must refuse, each for its reason.

    tests/static/stranger_cases.py

The script is what the Status workflow runs on a clone of the branch `status`
in a job with no token: cosign verifies every signed record and refuses a copy
of each with one byte appended. A check of signatures can pass for the wrong
reason in a few ways, and each is a case here, made from the signed records
under docs/runs:

    as kept            two signed records and one made before the repository
                       was public: accepted, and the count says two
    empty              a directory with nothing in it: nothing was checked
    nothing signed     only a record with no signature: nothing was checked
    a byte changed     a record with one byte appended beside its own bundle
    another's bundle   a record beside the bundle of a different record
    no record          a bundle with no record beside it
    lost signature     a record with no bundle, made after the first signed one
    accepts anything   a `cosign` that exits 0 whatever it is asked: the copy
                       with a byte appended is accepted, and that is a failure

A case that is refused for another reason than its own fails: a refusal that
comes from the wrong rule proves nothing about the right one.

The second half reads .github/workflows/status.yml: the job that runs the
script waits for the job that writes the branch, clones the branch, and is
given no token, no permission and no checkout that would carry one.
"""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNS = os.path.join(ROOT, "docs", "runs")
SCRIPT = os.path.join(ROOT, "scripts", "stranger.sh")
# Two signed records, the first two scheduled runs, and one from before the
# repository was public.
A, B, OLD = "43246322896", "43444481256", "43122643626"

failed = []


def put(d, run, record=True, bundle=True, of=None, as_run=None):
    """Copy a record of docs/runs and its bundle into d, under as_run's name;
    `of` takes the bundle from another run."""
    name = as_run or run
    if record:
        shutil.copy(os.path.join(RUNS, run + ".json"), os.path.join(d, name + ".json"))
    if bundle:
        shutil.copy(os.path.join(RUNS, (of or run) + ".json.sigstore.json"),
                    os.path.join(d, name + ".json.sigstore.json"))


def case(name, build, reason, says=None, first_on_path=None):
    d = tempfile.mkdtemp(prefix="stranger-")
    try:
        build(d)
        env = dict(os.environ)
        if first_on_path:
            env["PATH"] = first_on_path + os.pathsep + env["PATH"]
        r = subprocess.run([SCRIPT, d], capture_output=True, text=True, env=env)
        said = (r.stdout + r.stderr).strip()
        if reason is None:
            if r.returncode != 0:
                failed.append("%s: refused: %s" % (name, said))
            elif says and says not in said:
                failed.append("%s: accepted, and does not say %r: %s" % (name, says, said))
        elif r.returncode == 0:
            failed.append("%s: accepted: %s" % (name, said))
        elif reason not in said:
            failed.append("%s: refused, and not for its reason (%r): %s" % (name, reason, said))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def changed(d):
    put(d, A)
    with open(os.path.join(d, A + ".json"), "a", encoding="utf-8") as f:
        f.write(" ")


def lost(d):
    put(d, A)
    put(d, B, bundle=False)


case("as kept", lambda d: (put(d, A), put(d, B), put(d, OLD, bundle=False)), None,
     says="2 signed records")
case("empty", lambda d: None, "nothing was checked")
case("nothing signed", lambda d: put(d, OLD, bundle=False), "nothing was checked")
case("a byte changed", changed, "cosign does not verify it")
case("another's bundle", lambda d: put(d, A, of=B), "cosign does not verify it")
case("no record", lambda d: (put(d, A), put(d, B, record=False)), "a signature with no record beside it")
case("lost signature", lost, "a record with no signature, made after the first signed one")

# A verifier that accepts anything, first on PATH.
stub = tempfile.mkdtemp(prefix="stranger-stub-")
try:
    path = os.path.join(stub, "cosign")
    with open(path, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nexit 0\n")
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    case("accepts anything", lambda d: put(d, A), "cosign accepts a copy with one byte appended",
         first_on_path=stub)
finally:
    shutil.rmtree(stub, ignore_errors=True)

# The job that runs it.
workflow = open(os.path.join(ROOT, ".github", "workflows", "status.yml"), encoding="utf-8").read()
job = re.search(r"^  stranger:\n(.*?)(?=^  \S|\Z)", workflow, re.S | re.M)
if not job:
    failed.append("status.yml: no job `stranger` reads the branch back")
else:
    lines = [l for l in job.group(1).splitlines() if not l.strip().startswith("#")]
    body = "\n".join(lines)
    wants = {
        "    needs: status": "does not wait for the job that writes the branch",
        "    permissions: {}": "is given a permission",
        'git clone -q --depth 1 --branch status "https://github.com/$REPO.git" "$RUNNER_TEMP/branch"':
            "does not clone the branch `status` the way a reader would",
        '"$RUNNER_TEMP/code/scripts/stranger.sh" "$RUNNER_TEMP/branch/runs"':
            "does not run scripts/stranger.sh on the branch's records",
    }
    for text, why in wants.items():
        if text not in lines and text not in body:
            failed.append("status.yml: the job `stranger` %s" % why)
    for word in ("secrets.", "github.token", "GITHUB_TOKEN", "GH_TOKEN", "actions/checkout"):
        if word in body:
            failed.append("status.yml: the job `stranger` names %s: what it reads, anyone must be able to read" % word)

if failed:
    print("\n".join(failed))
    sys.exit(1)
print("scripts/stranger.sh accepts the records as kept and refuses seven directories, each for its reason; "
      "the Status workflow runs it on a clone of the branch, with no token")
