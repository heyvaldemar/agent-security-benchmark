#!/usr/bin/env python3
"""numbers.py - a run's record, and the README's tables made from it.

    numbers.py record DIR > docs/runs/<run id>.json
                                   one record from a run's downloaded
                                   artifacts (`gh run download <id> -D DIR`):
                                   every job's results.json, their legs together
    numbers.py tables RECORD       the tables, as the README carries them
    numbers.py check [--write]     every block in README.md between
                                   <!-- numbers: docs/runs/<id>.json NAME --> and
                                   <!-- /numbers --> is what `tables` prints for
                                   that record; --write puts it there

No number in the README is typed by hand (AGENTS.md). A record is what the
run's own jobs uploaded, kept in the repository under the run's id, so a
table can be made again from it by anyone and `scripts/validate.sh numbers`
can fail when the README says something the record does not.

Standard library only.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STANDINS = ("obedient", "deaf")
BOUNDARIES = {"sandbox": "kubernetes-ai-agent-sandbox", "flagship": "kubernetes-air-gapped-ai-agent",
              "cypress": "cypress-cloud-triage-agent"}
BLOCK = re.compile(r"(<!-- numbers: (\S+) (\S+) -->\n)(.*?)(<!-- /numbers -->)", re.S)


def record(directory):
    parts = [json.load(open(p, encoding="utf-8"))
             for p in sorted(glob.glob(os.path.join(directory, "**", "results.json"), recursive=True))]
    if not parts:
        sys.exit("no results.json under %s" % directory)
    runs = {json.dumps(p["run"], sort_keys=True) for p in parts}
    suites = {p["suite_sha256"] for p in parts}
    if len(runs) != 1 or len(suites) != 1:
        sys.exit("the artifacts under %s are not one run's: %d runs, %d suites" % (directory, len(runs), len(suites)))
    legs = sorted((leg for p in parts for leg in p["legs"]), key=lambda x: (x["boundary"], x["model"]))
    # Every check a leg's job made, not only the reader's: admission's plants,
    # the controls, the release's own run. Each job wrote them beside its record.
    for p in glob.glob(os.path.join(directory, "**", "e2e-results-*.json"), recursive=True):
        job = json.load(open(p, encoding="utf-8"))
        for leg in legs:
            if (leg["boundary"], leg["model"]) == (job.get("boundary"), job.get("model")):
                leg["job_checks"] = job["checks"]
    checks = [c for leg in legs for c in leg.get("job_checks", leg["checks"])]
    return {"schema": 1, "run": parts[0]["run"], "suite_sha256": parts[0]["suite_sha256"], "legs": legs,
            "checks_passed": sum(c["passed"] for c in checks), "checks_failed": sum(not c["passed"] for c in checks)}


def cell(leg):
    if leg is None:
        return "not run"
    n, acted = len(leg["attempts"]), sum(a["acted"] for a in leg["attempts"])
    saw = sum(bool(a.get("saw_the_plant")) for a in leg["attempts"])
    return "%d of %d" % (acted, n) + ("" if saw == n else " (read in %d)" % saw)


def tables(rec):
    legs = rec["legs"]
    real = [x for x in legs if x["model"] not in STANDINS]
    models = sorted({x["model"] for x in real})
    bounds = [b for b in ("flagship", "sandbox", "cypress") if any(x["boundary"] == b for x in real)]
    by = {(x["boundary"], x["model"]): x for x in legs}
    out = {}

    rows = ["| Model | " + " | ".join("At the %s's boundary" % b for b in bounds) + " |",
            "|---|" + "---|" * len(bounds)]
    for m in models:
        rows.append("| %s | " % m + " | ".join(cell(by.get((b, m))) for b in bounds) + " |")
    out["models"] = "\n".join(rows)

    rows = ["| Boundary | Release | Attempts | Tried to leave | Reached the outside | Stopped by | Asked for a tool not granted | Refused |",
            "|---|---|---|---|---|---|---|---|"]
    for b in bounds:
        mine = [x for x in real if x["boundary"] == b]
        rec_ = [x["boundary_record"] for x in mine]
        leave = sum(r["tried_to_leave"] for r in rec_)
        reach = sum(r["tried_to_reach"] for r in rec_)
        stopped = {}
        refused = 0
        for x in mine:
            for a in x["attempts"]:
                for t in a["tried"]:
                    if t["ask"] == "leave" and t["outcome"] != "reached":
                        stopped[t["stopped_by"]] = stopped.get(t["stopped_by"], 0) + 1
                    refused += t["ask"] == "reach" and t["outcome"] != "reached"
        tag = (mine[0].get("source") or {}).get("tag", "?")
        can_reach = any("reach" in a["asked"] for x in mine for a in x["attempts"])
        rows.append("| %s | %s | %d | %d calls | **%d** | %s | %s | %s |" % (
            BOUNDARIES[b], tag, sum(len(x["attempts"]) for x in mine), leave, sum(r["reached_outside"] for r in rec_),
            ", ".join("%s %d" % kv for kv in sorted(stopped.items(), key=lambda kv: -kv[1])) or "nothing was tried",
            "%d calls" % reach if can_reach else "cannot be asked there",
            "%d" % refused if can_reach else ""))
    out["boundaries"] = "\n".join(rows)

    seen = {a["dressing"] for x in real for a in x["attempts"]}
    suite = json.load(open(os.path.join(ROOT, "suite", "suite.json"), encoding="utf-8"))
    dressings = [d["id"] for d in suite["dressings"] if d["id"] in seen] + sorted(seen - {d["id"] for d in suite["dressings"]})
    rows = ["| Model | Boundary | " + " | ".join("`%s`" % d for d in dressings) + " |", "|---|---|" + "---|" * len(dressings)]
    for m in models:
        for b in bounds:
            leg = by.get((b, m))
            if leg is None:
                continue
            k = {}
            for a in leg["attempts"]:
                c = k.setdefault(a["dressing"], [0, 0])
                c[0] += a["acted"]
                c[1] += 1
            rows.append("| %s | %s | " % (m, b) + " | ".join("%d of %d" % tuple(k.get(d, [0, 0])) for d in dressings) + " |")
    out["dressings"] = "\n".join(rows)

    rows = ["| Stand-in | Read as acting on | Tried to leave | Reached the outside | With the door planted open |", "|---|---|---|---|---|"]
    for m in STANDINS:
        for x in legs:
            if x["model"] != m:
                continue
            door = x.get("open_door")
            rows.append("| `%s` | %d of %d plants | %d calls | **%d** | %s |" % (
                m, sum(a["acted"] for a in x["attempts"]), len(x["attempts"]), x["boundary_record"]["tried_to_leave"],
                x["boundary_record"]["reached_outside"],
                "%d heard, the gate %s" % (door["heard"], "failed" if door["gate_failed"] else "passed") if door else "not applied"))
    out["calibration"] = "\n".join(rows)

    own = [x for x in real if x.get("own_gates")]
    out["run"] = "Run [%s](%s), commit `%s`: %d of %d checks." % (
        rec["run"]["id"], rec["run"]["url"], rec["run"]["commit"], rec["checks_passed"],
        rec["checks_passed"] + rec["checks_failed"]) + (
        " The flagship's own gates held in every job: %s." % ", ".join(
            "%d of %d" % (x["own_gates"]["held"], x["own_gates"]["of"]) for x in own) if own else "")
    return out


def check(write):
    path = os.environ.get("README", os.path.join(ROOT, "README.md"))
    text = open(path, encoding="utf-8").read()
    bad, cache = [], {}

    def block(m):
        source, name = m.group(2), m.group(3)
        try:
            made = cache.setdefault(source, tables(json.load(open(os.path.join(ROOT, source), encoding="utf-8"))))
        except (OSError, ValueError) as e:
            bad.append("README takes numbers from %s, which cannot be read: %s" % (source, e))
            return m.group(0)
        if name not in made:
            bad.append("README asks %s for a table named %s" % (source, name))
            return m.group(0)
        want = made[name] + "\n"
        if m.group(4) != want and not write:
            bad.append("README's %s is not what %s holds" % (name, source))
        return m.group(1) + want + m.group(5)

    new = BLOCK.sub(block, text)
    if not BLOCK.search(text):
        bad.append("README carries no numbers from a run's record")
    if write and new != text:
        open(path, "w", encoding="utf-8").write(new)
    for line in bad:
        print("  FAIL  " + line)
    if not bad:
        print("  ok    every number in the README's tables is its run's record: %s"
              % ", ".join(sorted(set(m.group(2) for m in BLOCK.finditer(new)))))
    return 1 if bad else 0


def main(argv):
    if argv[:1] == ["record"] and len(argv) == 2:
        print(json.dumps(record(argv[1]), indent=1, ensure_ascii=False))
        return 0
    if argv[:1] == ["tables"] and len(argv) == 2:
        for name, table in tables(json.load(open(argv[1], encoding="utf-8"))).items():
            print("## %s\n%s\n" % (name, table))
        return 0
    if argv[:1] == ["check"]:
        return check("--write" in argv)
    sys.exit(__doc__.split("\n\n")[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
