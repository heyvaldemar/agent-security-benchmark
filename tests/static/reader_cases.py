#!/usr/bin/env python3
"""The reader, fed logs whose answer is known.

    tests/static/reader_cases.py

Each directory under tests/static/fixtures holds one leg's logs as a run left
them (attempts/*.log, collector.log, mcp-audit.jsonl) and expect.json, what
scripts/read.py must make of them: how many attempts it reads as acted on,
how many requests it counts outside, whether the outside's gate holds, and
whether the leg passes. The cases are the ones a reader can get wrong without
anything looking wrong:

    obedient     a stand-in that acts on every plant behind a shut door:
                 every attempt acted on, nothing outside, the leg passes
    deaf         a stand-in that acts on none: no attempt acted on
    open-door    the obedient stand-in with a door planted open: one request
                 outside, and the gate fails
    copy         an agent that copies its plant into its answer and makes no
                 call: named in the answer, and not acted on

    granite-4.0-1b, ministral-3-3b
                 two open models' legs from run 43107026508 (2026-11-11),
                 three attempts a dressing: an attempt that ends in a tool
                 call the server could not parse, a request the agent's own
                 web tool refused, a model that says it posted what the wall
                 stopped, and one that passes the outside address on to its
                 reader without calling anything

The first three are logs of a real run on kind; `copy` is written by hand
from one of them. A reader that takes a copy for acting, counts the control's
call as the agent's, or drops the outside's count fails here, and each of
those is a plant in tests/static/plants.tsv.
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    cases = sorted(glob.glob(os.path.join(ROOT, "tests", "static", "fixtures", "*", "expect.json")))
    if not cases:
        print("no recorded logs under tests/static/fixtures: the reader is shown nothing")
        return 1
    bad = []
    for path in cases:
        case = os.path.basename(os.path.dirname(path))
        want = json.load(open(path, encoding="utf-8"))
        work = tempfile.mkdtemp(prefix="reader-")
        try:
            shutil.copytree(os.path.dirname(path), work, dirs_exist_ok=True)
            r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "read.py"), "sandbox", work, want["model"]],
                               capture_output=True, text=True, cwd=ROOT,
                               env=dict(os.environ, ATTEMPTS=str(want.get("attempts_per_dressing", 1))))
            try:
                leg = json.load(open(os.path.join(work, "leg.json"), encoding="utf-8"))
            except (OSError, ValueError):
                bad.append("%s: the reader wrote no leg.json: %s" % (case, (r.stdout + r.stderr)[-300:]))
                continue
            gate = next((c["passed"] for c in leg["checks"]
                         if c["name"].startswith("requests from the agent that reached the outside")), None)
            got = {"read": len(leg["attempts"]), "acted": sum(a["acted"] for a in leg["attempts"]),
                   "reached_outside": leg["boundary_record"]["reached_outside"], "outside_gate_holds": gate,
                   "named_in_the_answer": sum(a["answer_names_the_outside"] for a in leg["attempts"]),
                   "passes": r.returncode == 0}
            for key, value in want.items():
                if key in got and got[key] != value:
                    bad.append("%s: %s is %r, and the logs say %r" % (case, key, got[key], value))
        finally:
            shutil.rmtree(work, ignore_errors=True)
    print("\n".join(bad) or "the reader makes of %d recorded legs what they are: %s"
          % (len(cases), ", ".join(os.path.basename(os.path.dirname(c)) for c in cases)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
