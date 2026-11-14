#!/usr/bin/env python3
"""scripts/stranger.sh, shown the directories it must refuse, each for its reason.

    tests/static/stranger_cases.py

The script is what the Status workflow runs on a clone of the branch `status`
in a job with no token: every record is the run its name says, cosign verifies
every signed one and refuses a copy of each with one byte appended, and only
the records made before the repository was public are without a signature. A
check of signatures can pass for the wrong reason in more ways than it can
fail, and each is a case here, made from the signed records under docs/runs:

    as kept            two signed records and one made before the repository
                       was public: accepted, and the count says two
    held               the same, and a second directory whose signed record
                       is among them: accepted
    empty              a directory with nothing in it: nothing was checked
    nothing signed     only a record with no signature: nothing was checked
    a byte changed     a record with one byte appended beside its own bundle
    another's bundle   a record beside the bundle of a different record
    no record          a bundle with no record beside it
    lost signature     a record of a run after the repository went public,
                       with no bundle
    an old id          a record nobody signed, under a run id lower than every
                       signed one: the list of unsigned runs is the script's,
                       not something the directory can move
    an old one changed a record made before the repository was public, with
                       one byte appended: no signature holds it, so the
                       script's sha256 for it has to
    another's name     a signed record and its bundle under another run's id
    no run id          a record whose name is not a run id
    not a record       a run id's name on a file that is no record
    not held           a signed record of the second directory that the first
                       does not hold
    held to nothing    a second directory with no signed record in it
    two files, a name  an unsigned record the second directory has, and other
                       bytes under its name in the first
    accepts anything   a `cosign` that exits 0 whatever it is asked: the copy
                       with a byte appended is accepted, and that is a failure
    no copy            a place where the copy cannot be written: cosign
                       would refuse what it was shown, having been shown
                       nothing
    nowhere            a `mktemp` that fails: no directory to make the copy in

A case that is refused for another reason than its own fails: a refusal that
comes from the wrong rule proves nothing about the right one.

The second half reads .github/workflows/status.yml: the job that runs the
script waits for the job that writes the branch, clones the branch, holds it
to docs/runs, and is given no token, no permission and no checkout that would
carry one.
"""
import json
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
# repository was public. NEW is a run id no record has.
A, B, OLD, NEW = "43246322896", "43444481256", "43122643626", "43999999999"

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


def write(d, name, text):
    with open(os.path.join(d, name), "w", encoding="utf-8") as f:
        f.write(text)


def stub(name, script="#!/bin/sh\nexit 0\n"):
    """A directory to put first on PATH, with one command in it that does
    nothing and says it succeeded."""
    d = tempfile.mkdtemp(prefix="stranger-stub-")
    path = os.path.join(d, name)
    write(d, name, script)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return d


def case(name, build, reason, says=None, kept=None, first_on_path=None):
    d = tempfile.mkdtemp(prefix="stranger-")
    k = tempfile.mkdtemp(prefix="stranger-kept-") if kept else None
    try:
        build(d)
        if kept:
            kept(k)
        e = dict(os.environ)
        if first_on_path:
            e["PATH"] = first_on_path + os.pathsep + e["PATH"]
        r = subprocess.run([SCRIPT, d] + ([k] if k else []), capture_output=True, text=True, env=e)
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
        if k:
            shutil.rmtree(k, ignore_errors=True)
        if first_on_path:
            shutil.rmtree(first_on_path, ignore_errors=True)


def as_kept(d):
    put(d, A)
    put(d, B)
    put(d, OLD, bundle=False)


def changed(d, run=A, bundle=True):
    put(d, run, bundle=bundle)
    with open(os.path.join(d, run + ".json"), "a", encoding="utf-8") as f:
        f.write(" ")


NO_SIGNATURE = "a record with no signature, and not one of those made before the repository was public"

case("as kept", as_kept, None, says="2 signed records")
case("held", as_kept, None, says="the 1 signed records", kept=lambda k: put(k, A))
case("empty", lambda d: None, "nothing was checked")
case("nothing signed", lambda d: put(d, OLD, bundle=False), "nothing was checked")
case("a byte changed", changed, "cosign does not verify it")
case("another's bundle", lambda d: put(d, A, of=B), "cosign does not verify it")
case("no record", lambda d: (put(d, A), put(d, B, record=False)), "a signature with no record beside it")
case("lost signature", lambda d: (put(d, A), put(d, B, bundle=False)), NO_SIGNATURE)
case("an old id", lambda d: (put(d, A), write(d, "1.json", json.dumps({"run": {"id": 1}}))), NO_SIGNATURE)
case("an old one changed", lambda d: (put(d, A), changed(d, OLD, bundle=False)),
     "a record made before the repository was public, and not the bytes this script has for it")
case("another's name", lambda d: (put(d, A), put(d, B, as_run=NEW)), "the record inside is run %s's, not %s's" % (B, NEW))
case("no run id", lambda d: (put(d, A), put(d, OLD, bundle=False, as_run="latest")), "a record whose name is not a run id")
case("not a record", lambda d: (put(d, A), write(d, NEW + ".json", "not a record\n")), "the record inside is run nobody's")
case("not held", lambda d: put(d, B), "does not hold the same two files", kept=lambda k: put(k, A))
case("held to nothing", as_kept, "was held to nothing", kept=lambda k: put(k, OLD, bundle=False))
case("two files, a name", as_kept, "hold different files under this name",
     kept=lambda k: (put(k, A), changed(k, OLD, bundle=False)))
case("accepts anything", lambda d: put(d, A), "cosign accepts a copy with one byte appended",
     first_on_path=stub("cosign"))
# A `mktemp` that answers with a path under a file: nothing can be written
# there, by root either.
case("no copy", lambda d: put(d, A), "the copy with one byte appended could not be made",
     first_on_path=stub("mktemp", '#!/bin/sh\necho "$0/nowhere"\n'))
case("nowhere", lambda d: put(d, A), "could not make a directory for the changed copies",
     first_on_path=stub("mktemp", "#!/bin/sh\nexit 1\n"))

# The job that runs it.
workflow = open(os.path.join(ROOT, ".github", "workflows", "status.yml"), encoding="utf-8").read()
job = re.search(r"^  stranger:\n(.*?)(?=^  \S|\Z)", workflow, re.S | re.M)
if not job:
    failed.append("status.yml: no job `stranger` reads the branch back")
else:
    lines = [l for l in job.group(1).splitlines() if not l.strip().startswith("#")]
    body = "\n".join(lines)
    whole = {
        "    needs: status": "does not wait for the job that writes the branch",
        "    permissions: {}": "is given a permission",
    }
    part = {
        'git clone -q --depth 1 --branch status "https://github.com/$REPO.git" "$RUNNER_TEMP/branch"':
            "does not clone the branch `status` the way a reader would",
        '"$RUNNER_TEMP/code/scripts/stranger.sh" "$RUNNER_TEMP/branch/runs" "$RUNNER_TEMP/code/docs/runs"':
            "does not run scripts/stranger.sh on the branch's records and hold them to docs/runs",
    }
    for text, why in whole.items():
        if text not in lines:
            failed.append("status.yml: the job `stranger` %s" % why)
    for text, why in part.items():
        if text not in body:
            failed.append("status.yml: the job `stranger` %s" % why)
    for word in ("secrets.", "github.token", "GITHUB_TOKEN", "GH_TOKEN", "actions/checkout"):
        if word in body:
            failed.append("status.yml: the job `stranger` names %s: what it reads, anyone must be able to read" % word)

if failed:
    print("\n".join(failed))
    sys.exit(1)
print("scripts/stranger.sh accepts the records as kept and refuses seventeen directories, each for its reason; "
      "the Status workflow runs it on a clone of the branch, with no token")
