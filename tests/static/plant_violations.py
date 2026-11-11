#!/usr/bin/env python3
"""Every static check, shown the violation it exists for, has to fail.

    tests/static/plant_violations.py

A check that cannot fail is not a check. Each line of tests/static/plants.tsv
names a file, a piece of it, its replacement, and the check in
scripts/validate.sh that must catch it: a reader that takes a copy of a plant
for acting on it, a renderer that changes a dressing's words, a wall with a
second way through. Each plant goes
into its own copy of the repository; the run fails if the named check stays
green, or if the text a plant breaks is no longer in the file (a stale plant
would prove nothing while looking like a pass).

Run scripts/validate.sh first: the untouched tree has to pass every check.
The verified releases under .cache/ are copied with the tree, so a plant
verifies nothing again.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# What a copy leaves behind: the git directory, a run's output, the pinned
# tools and the downloaded archives. Nothing a check reads: the recorded legs
# under tests/static/fixtures are logs, and they travel with the copy.
IGNORE = shutil.ignore_patterns(".git", "out", "bin", "release", "kubeconfig", "work", "models")


def unplanted():
    """A copy with no plant in it has to pass every check. If it does not,
    every plant below would be "caught" by a copy that fails on its own."""
    work = tempfile.mkdtemp(prefix="plant-")
    try:
        shutil.copytree(ROOT, work, dirs_exist_ok=True, symlinks=True, ignore=IGNORE)
        r = subprocess.run([os.path.join(work, "scripts", "validate.sh")], capture_output=True, text=True, cwd=work)
        failed = [l for l in r.stdout.splitlines() if l.startswith("-- ") and l.endswith(": FAILED")]
        if r.returncode != 0 or failed:
            print("a copy with no plant in it fails %s: no plant below would prove anything" % (", ".join(failed) or "to run"))
            print("\n".join("          " + l for l in r.stdout.splitlines()[-15:]))
            sys.exit(1)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    plants = []
    with open(os.path.join(ROOT, "tests", "static", "plants.tsv"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            plants.append([json.loads(x) for x in line.rstrip("\n").split("\t")])
    unplanted()
    missed = stale = 0
    for fname, old, new, check, what in plants:
        work = tempfile.mkdtemp(prefix="plant-")
        try:
            shutil.copytree(ROOT, work, dirs_exist_ok=True, symlinks=True,
                            ignore=IGNORE)
            path = os.path.join(work, fname)
            text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
            if old not in text:
                print("  STALE   %-12s %s: the text it breaks is no longer in %s" % (check, what, fname))
                stale += 1
                continue
            # An empty `old` plants a new file, in a new directory if need be.
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
            checks = [check]
            r = subprocess.run([os.path.join(work, "scripts", "validate.sh")] + checks,
                               capture_output=True, text=True, cwd=work)
            caught = "-- %s: FAILED" % check in r.stdout
            if caught:
                print("  caught  %-12s %s" % (check, what))
            else:
                print("  MISSED  %-12s %s" % (check, what))
                print("\n".join("          " + l for l in r.stdout.splitlines()[-15:]))
                missed += 1
        finally:
            shutil.rmtree(work, ignore_errors=True)
    print("%d plants: %d caught, %d missed, %d stale" % (len(plants), len(plants) - missed - stale, missed, stale))
    sys.exit(1 if (missed or stale) else 0)


if __name__ == "__main__":
    main()
